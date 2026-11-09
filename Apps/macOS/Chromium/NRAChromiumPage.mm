// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Nera's CEF bridge: one CEF browser per Nera page. Written for Nera against CEF's public API.
// Maps CEF handlers to NRAChromiumPageDelegate; all CEF types stay in this file.
#import "NRAChromiumPage.h"
#import "NRAChromium.h"

#include <cmath>
#include <map>
#include <string>

#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_image.h"
#include "include/cef_cookie.h"
#include "include/cef_permission_handler.h"
#include "include/cef_request_context.h"
#include "include/cef_request_context_handler.h"

extern std::string gRootCachePath;      // NRAChromium.mm
extern std::string gExtensionsProfile;  // NRAChromium.mm

namespace {

NSString *NS(const CefString &s) { return [NSString stringWithUTF8String:s.ToString().c_str()] ?: @""; }

/// One request context per storage key: pages of the same profile (or private session) share it.
std::map<std::string, CefRefPtr<CefRequestContext>> &Contexts() {
    static std::map<std::string, CefRefPtr<CefRequestContext>> contexts;
    return contexts;
}

/// Persistent profiles initialize asynchronously. A browser created before its context is ready never loads
/// (found 2026-10-29), so page creation waits for OnRequestContextInitialized.
std::map<std::string, bool> &ContextReady() {
    static std::map<std::string, bool> ready;
    return ready;
}
std::map<std::string, NSMutableArray<dispatch_block_t> *> &ContextWaiters() {
    static std::map<std::string, NSMutableArray<dispatch_block_t> *> waiters;
    return waiters;
}

std::string MapKey(const std::string &key, bool persistent) { return (persistent ? "p:" : "m:") + key; }


/// Per-profile privacy preferences (see ApplyGlobalPrivacy in NRAChromium.mm).
void ApplyProfilePrivacy(CefRefPtr<CefRequestContext> context) {
    if (!context) return;
    CefRefPtr<CefValue> disabled = CefValue::Create();
    disabled->SetInt(1);  // AIModeSettings policy: 1 = off (www.google.com/async/folae eligibility checks)
    CefString error;
    if (context->CanSetPreference("omnibox.ai_mode_settings")) context->SetPreference("omnibox.ai_mode_settings", disabled, error);
    // Chrome's built-in translate (Nera has no translate UI): its model and on-demand component downloads.
    CefRefPtr<CefValue> no = CefValue::Create();
    no->SetBool(false);
    if (context->CanSetPreference("translate.enabled")) context->SetPreference("translate.enabled", no, error);
}

class ContextHandler : public CefRequestContextHandler {
   public:
    explicit ContextHandler(std::string mapKey) : mapKey_(std::move(mapKey)) {}
    void OnRequestContextInitialized(CefRefPtr<CefRequestContext> context) override {
        ApplyProfilePrivacy(context);
        std::string key = mapKey_;
        dispatch_async(dispatch_get_main_queue(), ^{
            ContextReady()[key] = true;
            NSMutableArray<dispatch_block_t> *waiting = ContextWaiters()[key];
            ContextWaiters().erase(key);
            for (dispatch_block_t block in waiting) block();
        });
    }

   private:
    std::string mapKey_;
    IMPLEMENT_REFCOUNTING(ContextHandler);
};

CefRefPtr<CefRequestContext> ContextFor(const std::string &key, bool persistent);

/// Runs `block` once Chromium has started and the context for `key` is ready (immediately if both are).
void WhenContextReady(const std::string &key, bool persistent, dispatch_block_t block) {
    if (!NRAChromium.isStarted) {
        dispatch_block_t retry = [block copy];
        [NRAChromium whenStarted:^{ WhenContextReady(key, persistent, retry); }];
        return;
    }
    ContextFor(key, persistent);  // make sure it exists
    const std::string mapKey = MapKey(key, persistent);
    if (ContextReady()[mapKey]) return block();
    NSMutableArray<dispatch_block_t> *waiting = ContextWaiters()[mapKey] ?: [NSMutableArray array];
    [waiting addObject:[block copy]];
    ContextWaiters()[mapKey] = waiting;
}

CefRefPtr<CefRequestContext> ContextFor(const std::string &key, bool persistent) {
    // The extensions profile is Chromium's startup profile: the global context, where extensions are loaded.
    if (persistent && !gExtensionsProfile.empty() && key == gExtensionsProfile) {
        ContextReady()[MapKey(key, persistent)] = true;  // initialized with Chromium itself
        return CefRequestContext::GetGlobalContext();
    }
    auto &contexts = Contexts();
    auto it = contexts.find(MapKey(key, persistent));
    if (it != contexts.end()) return it->second;
    CefRequestContextSettings settings;
    if (persistent) {
        // Must be inside root_cache_path. Empty cache_path = memory only (private).
        // Chromium only creates profiles that sit directly inside its data folder (like Chrome's "Profile 1").
        // A nested path ("Profiles/<id>") silently fell back to memory: logins were lost at every quit (found
        // by the site check, 2026-10-29). Must match NRAChromium.mm's startup profile.
        CefString(&settings.cache_path) = gRootCachePath + "/Profile-" + key;
    }
    CefRefPtr<CefRequestContext> context = CefRequestContext::CreateContext(settings, new ContextHandler(MapKey(key, persistent)));
    contexts[MapKey(key, persistent)] = context;
    return context;
}

/// Counts the cookies Chromium accepted and reports once every one has been answered.
class CookieBatch : public CefSetCookieCallback {
   public:
    CookieBatch(NSInteger total, void (^completion)(NSInteger)) : remaining_(total), completion_([completion copy]) {}
    void OnComplete(bool success) override {
        if (success) added_++;
        if (--remaining_ == 0) Finish();
    }
    /// A cookie Chromium refused before trying to set it (its callback never runs).
    void Skip() {
        if (--remaining_ == 0) Finish();
    }

   private:
    void Finish() {
        NSInteger added = added_;
        void (^completion)(NSInteger) = completion_;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(added); });
    }
    NSInteger remaining_;
    NSInteger added_ = 0;
    void (^completion_)(NSInteger);
    IMPLEMENT_REFCOUNTING(CookieBatch);
};

/// Collects one site's cookies; reports once Chromium has released it (after the last cookie, or at once when
/// there are none: CEF then never calls Visit).
class SiteCookieCollector : public CefCookieVisitor {
   public:
    SiteCookieCollector(NSString *site, void (^completion)(NSArray *))
        : site_([site.lowercaseString copy]), completion_([completion copy]), cookies_([NSMutableArray array]) {}
    ~SiteCookieCollector() override {
        NSArray *cookies = [cookies_ copy];
        void (^completion)(NSArray *) = completion_;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(cookies); });
    }
    bool Visit(const CefCookie &cookie, int, int, bool &) override {
        NSString *domain = @(CefString(&cookie.domain).ToString().c_str());
        NSString *host = ([domain hasPrefix:@"."] ? [domain substringFromIndex:1] : domain).lowercaseString;
        if (![host isEqualToString:site_] && ![host hasSuffix:[@"." stringByAppendingString:site_]]) return true;
        NSMutableDictionary *item = [@{
            @"domain" : domain,
            @"name" : @(CefString(&cookie.name).ToString().c_str()),
            @"value" : @(CefString(&cookie.value).ToString().c_str()),
            @"path" : @(CefString(&cookie.path).ToString().c_str()),
            @"secure" : @(cookie.secure != 0),
            @"httpOnly" : @(cookie.httponly != 0),
        } mutableCopy];
        // Chromium time: microseconds since 1601-01-01 UTC.
        if (cookie.has_expires) item[@"expires"] = @((double)cookie.expires.val / 1000000.0 - 11644473600.0);
        switch (cookie.same_site) {
            case CEF_COOKIE_SAME_SITE_NO_RESTRICTION: item[@"sameSite"] = @"None"; break;
            case CEF_COOKIE_SAME_SITE_LAX_MODE: item[@"sameSite"] = @"Lax"; break;
            case CEF_COOKIE_SAME_SITE_STRICT_MODE: item[@"sameSite"] = @"Strict"; break;
            default: break;
        }
        [cookies_ addObject:item];
        return true;
    }

   private:
    NSString *site_;
    void (^completion_)(NSArray *);
    NSMutableArray *cookies_;
    IMPLEMENT_REFCOUNTING(SiteCookieCollector);
};

NRANavigationTrigger TriggerFor(CefRefPtr<CefRequest> request, bool userGesture, bool isRedirect) {
    if (isRedirect) return NRANavigationTriggerRedirect;
    const auto transition = request->GetTransitionType();
    const int source = transition & TT_SOURCE_MASK;
    // Browser-initiated: our LoadURL (explicit), reload, and back/forward from our UI.
    if ((transition & TT_FORWARD_BACK_FLAG) || source == TT_EXPLICIT || source == TT_RELOAD) return NRANavigationTriggerUserTyped;
    if (transition & TT_CLIENT_REDIRECT_FLAG) return NRANavigationTriggerRedirect;
    if (source == TT_LINK && userGesture) return NRANavigationTriggerLinkClick;
    return NRANavigationTriggerScript;
}

class PageClient : public CefClient,
                   public CefDisplayHandler,
                   public CefLoadHandler,
                   public CefRequestHandler,
                   public CefJSDialogHandler,
                   public CefDownloadHandler,
                   public CefFindHandler,
                   public CefKeyboardHandler,
                   public CefPermissionHandler,
                   public CefContextMenuHandler,
                   public CefLifeSpanHandler {
   public:
    PageClient(NRAChromiumPage *page, id<NRAChromiumPageDelegate> delegate) : page_(page), delegate_(delegate) {}

    /// After this, no delegate callbacks (NRAChromiumPage.close). Waiting scripts get nil.
    void Detach() {
        delegate_ = nil;
        for (auto &entry : evaluations_) entry.second(nil);
        evaluations_.clear();
    }

    /// Nera's scripts waiting for the renderer's answer, by request id.
    std::map<int, void (^)(NSString *)> evaluations_;
    int nextEvaluation_ = 0;

    /// Answers a waiting script once (the renderer's result, or nil after a timeout).
    void FinishEvaluation(int requestID, NSString *result) {
        auto it = evaluations_.find(requestID);
        if (it == evaluations_.end()) return;
        void (^completion)(NSString *) = it->second;
        evaluations_.erase(it);
        completion(result);
    }

    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
    CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
    CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
    CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
    CefRefPtr<CefFindHandler> GetFindHandler() override { return this; }
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }
    CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
    CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override { return this; }

    /// WebAuthn requests from Nera's renderer shim. The origin comes from the frame (browser process), never
    /// from the page; Swift checks it and asks the system authenticator (docs/security/passkeys.md).
    bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefProcessId,
                                  CefRefPtr<CefProcessMessage> message) override {
        if (message->GetName() == "nera.eval.result") {
            CefRefPtr<CefListValue> result = message->GetArgumentList();
            NSString *value = result->GetBool(1) ? NS(result->GetString(2)) : nil;
            FinishEvaluation(result->GetInt(0), value);
            return true;
        }
        if (message->GetName() != "nera.webauthn") return false;
        id<NRAChromiumPageDelegate> d = delegate_;
        CefRefPtr<CefListValue> args = message->GetArgumentList();
        const int requestID = args->GetInt(0);
        CefRefPtr<CefFrame> target = frame;
        auto answer = ^(BOOL ok, NSString *payload) {
            if (!target->IsValid()) return;
            CefRefPtr<CefProcessMessage> result = CefProcessMessage::Create("nera.webauthn.result");
            result->GetArgumentList()->SetInt(0, requestID);
            result->GetArgumentList()->SetBool(1, ok);
            result->GetArgumentList()->SetString(2, payload.UTF8String ?: "");
            target->SendProcessMessage(PID_RENDERER, result);
        };
        if (!d) {
            answer(NO, @"NotAllowedError|The page is closing.");
            return true;
        }
        [d chromiumPage:page_
                webAuthn:NS(args->GetString(1))
                    json:NS(args->GetString(2))
                frameURL:NS(frame->GetURL())
                  topURL:NS(browser->GetMainFrame()->GetURL())
                   reply:answer];
        return true;
    }

    /// "Inspect Element" while the user has developer tools turned on (SEC-056).
    bool devToolsEnabled_ = false;
    static constexpr int kInspectElement = MENU_ID_USER_FIRST;
    void OnBeforeContextMenu(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, CefRefPtr<CefContextMenuParams>,
                             CefRefPtr<CefMenuModel> model) override {
        if (!devToolsEnabled_) return;
        if (model->GetCount() > 0) model->AddSeparator();
        model->AddItem(kInspectElement, "Inspect Element");
    }
    bool OnContextMenuCommand(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame>, CefRefPtr<CefContextMenuParams> params,
                              int command, EventFlags) override {
        if (command != kInspectElement || !devToolsEnabled_) return false;
        CefWindowInfo window;
        CefBrowserSettings settings;
        browser->GetHost()->ShowDevTools(window, nullptr, settings, CefPoint(params->GetXCoord(), params->GetYCoord()));
        return true;
    }

    // Permissions go to Nera's per-site permission manager (SEC-040); anything Nera doesn't model is denied.
    bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, const CefString &origin, uint32_t requested,
                                        CefRefPtr<CefMediaAccessCallback> callback) override {
        id<NRAChromiumPageDelegate> d = delegate_;
        const uint32_t desktop = CEF_MEDIA_PERMISSION_DESKTOP_AUDIO_CAPTURE | CEF_MEDIA_PERMISSION_DESKTOP_VIDEO_CAPTURE;
        if (!d || (requested & desktop)) {  // screen capture isn't offered yet
            callback->Cancel();
            return true;
        }
        NRAPermissionKinds kinds = 0;
        if (requested & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE) kinds |= NRAPermissionCamera;
        if (requested & CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE) kinds |= NRAPermissionMicrophone;
        CefRefPtr<CefMediaAccessCallback> cb = callback;
        [d chromiumPage:page_ permissionRequestFromOrigin:NS(origin) kinds:kinds reply:^(BOOL granted) {
            if (granted) cb->Continue(requested); else cb->Cancel();
        }];
        return true;
    }

    bool OnShowPermissionPrompt(CefRefPtr<CefBrowser>, uint64_t, const CefString &origin, uint32_t requested,
                                CefRefPtr<CefPermissionPromptCallback> callback) override {
        id<NRAChromiumPageDelegate> d = delegate_;
        const uint32_t known = CEF_PERMISSION_TYPE_CAMERA_STREAM | CEF_PERMISSION_TYPE_MIC_STREAM | CEF_PERMISSION_TYPE_GEOLOCATION |
                               CEF_PERMISSION_TYPE_NOTIFICATIONS | CEF_PERMISSION_TYPE_CLIPBOARD;
        if (!d || (requested & ~known)) {  // anything Nera doesn't model yet is denied
            callback->Continue(CEF_PERMISSION_RESULT_DENY);
            return true;
        }
        NRAPermissionKinds kinds = 0;
        if (requested & CEF_PERMISSION_TYPE_CAMERA_STREAM) kinds |= NRAPermissionCamera;
        if (requested & CEF_PERMISSION_TYPE_MIC_STREAM) kinds |= NRAPermissionMicrophone;
        if (requested & CEF_PERMISSION_TYPE_GEOLOCATION) kinds |= NRAPermissionLocation;
        if (requested & CEF_PERMISSION_TYPE_NOTIFICATIONS) kinds |= NRAPermissionNotifications;
        if (requested & CEF_PERMISSION_TYPE_CLIPBOARD) kinds |= NRAPermissionClipboardRead;
        CefRefPtr<CefPermissionPromptCallback> cb = callback;
        [d chromiumPage:page_ permissionRequestFromOrigin:NS(origin) kinds:kinds reply:^(BOOL granted) {
            cb->Continue(granted ? CEF_PERMISSION_RESULT_ACCEPT : CEF_PERMISSION_RESULT_DENY);
        }];
        return true;
    }

    // Nera's menu shortcuts (⌘T, ⌘W, ⌘D, ⇧⌘T, …) win over the page, as in other browsers: Chromium's view
    // would otherwise send Command keys to the page and never back to the app's menu bar. Edit commands
    // (⌘C/⌘V/⌘Z…) still reach the page: the Edit menu sends them to the focused view.
    bool OnPreKeyEvent(CefRefPtr<CefBrowser>, const CefKeyEvent &event, CefEventHandle osEvent, bool *) override {
        if (event.type != KEYEVENT_RAWKEYDOWN || !(event.modifiers & EVENTFLAG_COMMAND_DOWN) || !osEvent) return false;
        NSEvent *keyEvent = (__bridge NSEvent *)osEvent;
        return [NSApp.mainMenu performKeyEquivalent:keyEvent];
    }

    // Navigation policy: every frame navigation goes through Nera's NavigationPolicy.
    bool OnBeforeBrowse(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, CefRefPtr<CefRequest> request, bool user_gesture,
                        bool is_redirect) override {
        id<NRAChromiumPageDelegate> d = delegate_;
        if (!d) return true;  // closed: cancel
        BOOL allow = [d chromiumPage:page_
                     shouldNavigateTo:NS(request->GetURL())
                            mainFrame:frame->IsMain()
                              trigger:TriggerFor(request, user_gesture, is_redirect)];
        return !allow;  // true cancels
    }

    void OnRenderProcessTerminated(CefRefPtr<CefBrowser>, TerminationStatus status, int, const CefString &) override {
        NRATermination reason = NRATerminationOther;
        switch (status) {
            case TS_PROCESS_CRASHED: reason = NRATerminationCrashed; break;
            case TS_PROCESS_WAS_KILLED: reason = NRATerminationKilled; break;
            case TS_PROCESS_OOM: reason = NRATerminationOutOfMemory; break;
            default: break;
        }
        [delegate_ chromiumPage:page_ processTerminated:reason];
    }

    // Load lifecycle (main frame only).
    void OnLoadStart(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, TransitionType) override {
        if (frame->IsMain()) [delegate_ chromiumPage:page_ didCommitURL:NS(frame->GetURL())];
    }
    void OnLoadEnd(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, int status) override {
        if (frame->IsMain()) [delegate_ chromiumPage:page_ didFinishURL:NS(frame->GetURL()) httpStatus:status];
    }
    void OnLoadError(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame> frame, ErrorCode code, const CefString &text,
                     const CefString &url) override {
        if (frame->IsMain()) [delegate_ chromiumPage:page_ didFailURL:NS(url) code:(int)code text:NS(text)];
    }
    void OnLoadingStateChange(CefRefPtr<CefBrowser>, bool loading, bool back, bool forward) override {
        [delegate_ chromiumPage:page_ loading:loading canGoBack:back canGoForward:forward];
    }

    // Display.
    void OnFaviconURLChange(CefRefPtr<CefBrowser> browser, const std::vector<CefString> &icon_urls) override;
    /// The page's icon, downloaded by Chromium (same cookies and network stack as the page), as PNG.
    void FaviconDownloaded(CefRefPtr<CefImage> image) {
        if (!image || image->IsEmpty() || !delegate_) return;
        int width = 0, height = 0;
        CefRefPtr<CefBinaryValue> png = image->GetAsPNG(2.0f, true, width, height);
        if (!png || png->GetSize() == 0 || png->GetSize() > 512 * 1024) return;
        NSMutableData *data = [NSMutableData dataWithLength:png->GetSize()];
        png->GetData(data.mutableBytes, data.length, 0);
        [delegate_ chromiumPage:page_ favicon:data];
    }
    void OnTitleChange(CefRefPtr<CefBrowser>, const CefString &title) override {
        [delegate_ chromiumPage:page_ titleChanged:NS(title)];
    }
    // The page's content now fills Nera's page area; Nera makes that area fill the screen.
    void OnFullscreenModeChange(CefRefPtr<CefBrowser>, bool fullscreen) override {
        [delegate_ chromiumPage:page_ fullscreen:fullscreen];
    }
    void OnLoadingProgressChange(CefRefPtr<CefBrowser>, double progress) override {
        [delegate_ chromiumPage:page_ progress:progress];
    }

    // JavaScript dialogs: always routed to Nera (never Chromium's own UI).
    bool OnJSDialog(CefRefPtr<CefBrowser>, const CefString &origin_url, JSDialogType type, const CefString &message,
                    const CefString &default_text, CefRefPtr<CefJSDialogCallback> callback, bool &) override {
        id<NRAChromiumPageDelegate> d = delegate_;
        if (!d) return false;
        NRADialogKind kind = type == JSDIALOGTYPE_ALERT ? NRADialogKindAlert
                             : type == JSDIALOGTYPE_CONFIRM ? NRADialogKindConfirm
                                                            : NRADialogKindPrompt;
        // The block owns the callback. If Swift drops the block, CEF's callback is released uncalled
        // and the dialog is cancelled: the same default-deny rule as Nera's Decision.
        CefRefPtr<CefJSDialogCallback> cb = callback;
        [d chromiumPage:page_
                 dialog:kind
              originURL:NS(origin_url)
                message:NS(message)
            defaultText:NS(default_text)
                  reply:^(BOOL ok, NSString *text) {
                      cb->Continue(ok, text ? text.UTF8String : "");
                  }];
        return true;
    }
    bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser>, const CefString &, bool, CefRefPtr<CefJSDialogCallback> callback) override {
        callback->Continue(true, "");  // beforeunload prompts aren't routed to Nera yet: allow leaving
        return true;
    }

    // Downloads.
    bool CanDownload(CefRefPtr<CefBrowser>, const CefString &, const CefString &) override { return delegate_ != nil; }
    bool OnBeforeDownload(CefRefPtr<CefBrowser>, CefRefPtr<CefDownloadItem> item, const CefString &suggested_name,
                          CefRefPtr<CefBeforeDownloadCallback> callback) override {
        id<NRAChromiumPageDelegate> d = delegate_;
        if (!d) return false;
        CefRefPtr<CefBeforeDownloadCallback> cb = callback;
        uint32_t downloadID = item->GetId();
        [d chromiumPage:page_
            downloadRequested:downloadID
                          url:NS(item->GetURL())
                suggestedName:NS(suggested_name)
                     mimeType:NS(item->GetMimeType())
                   totalBytes:item->GetTotalBytes()
                        reply:^(NSString *path) {
                            if (path) cb->Continue(path.UTF8String, false);
                            // nil: don't continue. The callback is released and CEF cancels the download.
                        }];
        return true;
    }
    /// Cancels a running download (its callback is kept while it runs).
    void CancelDownload(uint32_t downloadID) {
        auto it = downloadCallbacks_.find(downloadID);
        if (it != downloadCallbacks_.end()) it->second->Cancel();
    }
    void OnDownloadUpdated(CefRefPtr<CefBrowser>, CefRefPtr<CefDownloadItem> item, CefRefPtr<CefDownloadItemCallback> callback) override {
        if (item->IsComplete() || item->IsCanceled() || item->IsInterrupted()) downloadCallbacks_.erase(item->GetId());
        else downloadCallbacks_[item->GetId()] = callback;
        [delegate_ chromiumPage:page_
                       download:item->GetId()
                       received:item->GetReceivedBytes()
                          total:item->GetTotalBytes()
                       complete:item->IsComplete()
                       canceled:item->IsCanceled()
                    interrupted:item->IsInterrupted()
                           path:NS(item->GetFullPath())];
    }

    // Find in page.
    void OnFindResult(CefRefPtr<CefBrowser>, int, int count, const CefRect &, int active_match_ordinal, bool final_update) override {
        [delegate_ chromiumPage:page_ findMatches:count active:active_match_ordinal isFinal:final_update];
    }

    // Closing a page must never close Nera's window. CEF's default for a browser embedded in an app's view is
    // to close the top-level window that hosts it; returning true tells CEF the app handles that itself.
    bool DoClose(CefRefPtr<CefBrowser>) override { return true; }

    // Popups: denied until child pages are implemented (the adapter doesn't claim .childPages).
    bool OnBeforePopup(CefRefPtr<CefBrowser>, CefRefPtr<CefFrame>, int, const CefString &, const CefString &,
                       WindowOpenDisposition, bool, const CefPopupFeatures &, CefWindowInfo &, CefRefPtr<CefClient> &,
                       CefBrowserSettings &, CefRefPtr<CefDictionaryValue> &, bool *) override {
        return true;
    }

   private:
    __weak NRAChromiumPage *page_;
    __weak id<NRAChromiumPageDelegate> delegate_;
    std::map<uint32_t, CefRefPtr<CefDownloadItemCallback>> downloadCallbacks_;
    IMPLEMENT_REFCOUNTING(PageClient);
};

/// Delivers a downloaded favicon back to its page.
class FaviconCallback : public CefDownloadImageCallback {
   public:
    explicit FaviconCallback(CefRefPtr<PageClient> client) : client_(client) {}
    void OnDownloadImageFinished(const CefString &, int, CefRefPtr<CefImage> image) override { client_->FaviconDownloaded(image); }

   private:
    CefRefPtr<PageClient> client_;
    IMPLEMENT_REFCOUNTING(FaviconCallback);
};

void PageClient::OnFaviconURLChange(CefRefPtr<CefBrowser> browser, const std::vector<CefString> &icon_urls) {
    for (const auto &url : icon_urls) {
        std::string s = url.ToString();
        if (s.rfind("https://", 0) != 0 && s.rfind("http://", 0) != 0) continue;  // web icons only (no file:, data: is inline)
        browser->GetHost()->DownloadImage(url, true, 64, false, new FaviconCallback(this));
        return;
    }
}

}  // namespace

/// Holds Chromium's view and lays it out explicitly: it always fills this view. (Autoresizing masks can't be
/// trusted here: a container that is briefly zero-sized while SwiftUI sets up its layout leaves the child with a
/// wrong frame for good, and the page then shows nothing or is drawn shifted.)
@interface NRAPageHostView : NSView
@end

@implementation NRAPageHostView
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    for (NSView *child in self.subviews) child.frame = self.bounds;
}
- (void)didAddSubview:(NSView *)subview {
    [super didAddSubview:subview];
    subview.autoresizingMask = NSViewNotSizable;
    subview.frame = self.bounds;
}
@end

@implementation NRAChromiumPage {
    CefRefPtr<PageClient> _client;
    CefRefPtr<CefBrowser> _browser;
    NSView *_view;
    NSMutableArray<dispatch_block_t> *_pending;  // commands issued before the browser exists
    BOOL _closed;
}

/// Runs `block` now if the browser exists, or once it's created.
- (void)withBrowser:(dispatch_block_t)block {
    if (_closed) return;
    if (_browser) return block();
    [_pending addObject:[block copy]];
}

- (instancetype)initWithStorageKey:(NSString *)storageKey
                        persistent:(BOOL)persistent
                          passkeys:(BOOL)passkeys
                          delegate:(id<NRAChromiumPageDelegate>)delegate {
    if ((self = [super init])) {
        _view = [[NRAPageHostView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
        _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _client = new PageClient(self, delegate);
        _pending = [NSMutableArray array];
        const std::string key = storageKey.UTF8String;
        const bool wantsPasskeys = passkeys;
        __weak NRAChromiumPage *weakSelf = self;
        // Every CEF call waits until Chromium has started (on a first launch, when the welcome finishes) and the
        // profile's context is ready: before that, CEF's library isn't even loaded.
        WhenContextReady(key, persistent, ^{
            NRAChromiumPage *page = weakSelf;
            if (!page || page->_closed) return;
            CefWindowInfo window;
            window.SetAsChild((__bridge CefWindowHandle)page->_view, CefRect(0, 0, 800, 600));
            window.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
            CefBrowserSettings browserSettings;
            // Empty URL: no initial navigation, so the first load() produces exactly one lifecycle.
            // Read by the renderer helper (OnBrowserCreated): whether to expose PublicKeyCredential.
            CefRefPtr<CefDictionaryValue> extra = CefDictionaryValue::Create();
            extra->SetBool("nera.passkeys", wantsPasskeys);
            page->_browser = CefBrowserHost::CreateBrowserSync(window, page->_client, "", browserSettings, extra, ContextFor(key, persistent));
            if (!page->_browser) return;
            NSArray<dispatch_block_t> *queued = [page->_pending copy];
            [page->_pending removeAllObjects];
            for (dispatch_block_t block in queued) block();
        });
    }
    return self;
}

- (NSView *)view { return _view; }
- (void)loadURL:(NSString *)url {
    std::string target = url.UTF8String;
    [self withBrowser:^{ self->_browser->GetMainFrame()->LoadURL(target); }];
}
- (void)goBack { if (_browser) _browser->GoBack(); }
- (void)goForward { if (_browser) _browser->GoForward(); }
- (void)exitFullscreen {
    if (_browser) _browser->GetHost()->ExitFullscreen(true);
}
- (void)reload { if (_browser) _browser->Reload(); }
- (void)stop { if (_browser) _browser->StopLoad(); }
- (void)setZoomFactor:(double)factor {
    // Chromium zoom levels are logarithmic: factor = 1.2 ^ level.
    [self withBrowser:^{ self->_browser->GetHost()->SetZoomLevel(std::log(factor) / std::log(1.2)); }];
}
- (void)setMuted:(BOOL)muted {
    [self withBrowser:^{ self->_browser->GetHost()->SetAudioMuted(muted); }];
}
- (void)find:(NSString *)text forward:(BOOL)forward matchCase:(BOOL)matchCase findNext:(BOOL)findNext {
    if (_browser) _browser->GetHost()->Find(text.UTF8String, forward, matchCase, findNext);
}
- (void)stopFinding { if (_browser) _browser->GetHost()->StopFinding(true); }
- (void)startDownload:(NSString *)url {
    std::string target = url.UTF8String;
    [self withBrowser:^{ self->_browser->GetHost()->StartDownload(target); }];
}
- (void)cancelDownload:(uint32_t)downloadID { if (_client) _client->CancelDownload(downloadID); }
- (void)setDevToolsEnabled:(BOOL)enabled { if (_client) _client->devToolsEnabled_ = enabled; }
- (void)evaluate:(NSString *)script completion:(void (^)(NSString *_Nullable))completion {
    if (_closed || !_browser || !_client) return completion(nil);
    CefRefPtr<CefFrame> frame = _browser->GetMainFrame();
    if (!frame || !frame->IsValid()) return completion(nil);
    PageClient *client = _client.get();
    const int requestID = ++client->nextEvaluation_;
    client->evaluations_[requestID] = [completion copy];
    CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create("nera.eval");
    message->GetArgumentList()->SetInt(0, requestID);
    message->GetArgumentList()->SetString(1, script.UTF8String);
    frame->SendProcessMessage(PID_RENDERER, message);
    // A navigation can drop the request in the renderer: answer nil after 3 seconds at the latest.
    CefRefPtr<PageClient> keep = _client;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        keep->FinishEvaluation(requestID, nil);
    });
}
- (void)showDevTools {
    if (!_browser || !_client || !_client->devToolsEnabled_) return;
    CefWindowInfo window;
    CefBrowserSettings settings;
    _browser->GetHost()->ShowDevTools(window, nullptr, settings, CefPoint());
}

- (void)close {
    _closed = YES;
    [_pending removeAllObjects];
    _client->Detach();
    if (_browser) _browser->GetHost()->CloseBrowser(true);
    _browser = nullptr;
    [_view removeFromSuperview];
}

+ (void)removeDataForStorageKey:(NSString *)storageKey persistent:(BOOL)persistent completion:(void (^)(void))completion {
    if (!NRAChromium.isStarted) {
        NSString *key = [storageKey copy];
        void (^done)(void) = [completion copy];
        [NRAChromium whenStarted:^{ [NRAChromiumPage removeDataForStorageKey:key persistent:persistent completion:done]; }];
        return;
    }
    CefRefPtr<CefRequestContext> context = ContextFor(storageKey.UTF8String, persistent);
    context->ClearHttpCache(nullptr);
    context->GetCookieManager(nullptr)->DeleteCookies("", "", nullptr);
    completion();  // cache and cookie deletion are asynchronous in CEF; callers don't depend on completion yet
}

+ (void)setCookies:(NSArray<NSDictionary<NSString *, id> *> *)cookies
     forStorageKey:(NSString *)storageKey
        persistent:(BOOL)persistent
        completion:(void (^)(NSInteger added))completion {
    if (cookies.count == 0) return completion(0);
    const std::string key = storageKey.UTF8String;
    NSArray *batch = [cookies copy];
    // Answered exactly once: by Chromium, or with 0 if it never starts.
    __block BOOL answered = NO;
    void (^reply)(NSInteger) = [completion copy];
    void (^done)(NSInteger) = ^(NSInteger added) {
        if (answered) return;
        answered = YES;
        reply(added);
    };
    if (!NRAChromium.isStarted) [NRAChromium ifStartFails:^{ done(0); }];
    WhenContextReady(key, persistent, ^{
        CefRefPtr<CefCookieManager> manager = ContextFor(key, persistent)->GetCookieManager(nullptr);
        CefRefPtr<CookieBatch> counter = new CookieBatch((NSInteger)batch.count, done);
        if (!manager) {
            for (NSUInteger i = 0; i < batch.count; i++) counter->Skip();
            return;
        }
        for (NSDictionary *item in batch) {
            NSString *domain = item[@"domain"];
            NSString *path = item[@"path"] ?: @"/";
            BOOL secure = [item[@"secure"] boolValue];
            NSString *host = [domain hasPrefix:@"."] ? [domain substringFromIndex:1] : domain;
            NSString *url = [NSString stringWithFormat:@"%@://%@%@", secure ? @"https" : @"http", host, path];
            CefCookie cookie;
            CefString(&cookie.name) = [item[@"name"] UTF8String];
            CefString(&cookie.value) = [item[@"value"] UTF8String];
            CefString(&cookie.domain) = domain.UTF8String;
            CefString(&cookie.path) = path.UTF8String;
            cookie.secure = secure;
            cookie.httponly = [item[@"httpOnly"] boolValue];
            if (NSNumber *expires = item[@"expires"]) {
                cookie.has_expires = true;
                // Chromium time: microseconds since 1601-01-01 UTC.
                cookie.expires.val = (int64_t)((expires.doubleValue + 11644473600.0) * 1000000.0);
            }
            NSString *sameSite = item[@"sameSite"];
            cookie.same_site = [sameSite isEqualToString:@"None"]     ? CEF_COOKIE_SAME_SITE_NO_RESTRICTION
                               : [sameSite isEqualToString:@"Lax"]    ? CEF_COOKIE_SAME_SITE_LAX_MODE
                               : [sameSite isEqualToString:@"Strict"] ? CEF_COOKIE_SAME_SITE_STRICT_MODE
                                                                      : CEF_COOKIE_SAME_SITE_UNSPECIFIED;
            if (!manager->SetCookie(url.UTF8String, cookie, counter)) counter->Skip();
        }
    });
}

+ (void)cookiesForSite:(NSString *)site
         storageKey:(NSString *)storageKey
         persistent:(BOOL)persistent
         completion:(void (^)(NSArray<NSDictionary<NSString *, id> *> *))completion {
    if (!NRAChromium.isStarted) return completion(@[]);
    const std::string key = storageKey.UTF8String;
    NSString *siteCopy = [site copy];
    void (^reply)(NSArray *) = [completion copy];
    WhenContextReady(key, persistent, ^{
        CefRefPtr<CefCookieManager> manager = ContextFor(key, persistent)->GetCookieManager(nullptr);
        CefRefPtr<SiteCookieCollector> collector = new SiteCookieCollector(siteCopy, reply);
        if (manager) manager->VisitAllCookies(collector);
    });
}

@end

