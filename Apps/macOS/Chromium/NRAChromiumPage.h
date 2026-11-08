// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Nera's CEF bridge: one browser per Nera page (embedded hosting, ADR-0009). No CEF types cross this
// header; CEFBackend.swift adapts it to ChromiumEngine's ChromiumBackend port (ADR-0010).
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// What started a navigation, already mapped to Nera's `NavigationPolicy.Trigger`.
typedef NS_ENUM(NSInteger, NRANavigationTrigger) {
    NRANavigationTriggerUserTyped,  // our own load, back/forward, reload
    NRANavigationTriggerLinkClick,  // link with a user gesture
    NRANavigationTriggerScript,     // anything the page did without a gesture
    NRANavigationTriggerRedirect,
};

typedef NS_ENUM(NSInteger, NRADialogKind) { NRADialogKindAlert, NRADialogKindConfirm, NRADialogKindPrompt };

typedef NS_ENUM(NSInteger, NRATermination) {
    NRATerminationCrashed,
    NRATerminationKilled,
    NRATerminationOutOfMemory,
    NRATerminationOther,
};

typedef NS_OPTIONS(NSUInteger, NRAPermissionKinds) {
    NRAPermissionCamera = 1 << 0,
    NRAPermissionMicrophone = 1 << 1,
    NRAPermissionLocation = 1 << 2,
    NRAPermissionNotifications = 1 << 3,
    NRAPermissionClipboardRead = 1 << 4,
};

@class NRAChromiumPage;

/// Every callback arrives on the main thread (CEF's UI thread is the AppKit main thread here).
@protocol NRAChromiumPageDelegate <NSObject>
/// Synchronous policy check for every frame navigation. Return NO to cancel it.
- (BOOL)chromiumPage:(NRAChromiumPage *)page
    shouldNavigateTo:(NSString *)url
           mainFrame:(BOOL)mainFrame
             trigger:(NRANavigationTrigger)trigger;
- (void)chromiumPage:(NRAChromiumPage *)page didCommitURL:(NSString *)url;
- (void)chromiumPage:(NRAChromiumPage *)page didFinishURL:(NSString *)url httpStatus:(int)status;
- (void)chromiumPage:(NRAChromiumPage *)page didFailURL:(NSString *)url code:(int)code text:(NSString *)text;
- (void)chromiumPage:(NRAChromiumPage *)page titleChanged:(NSString *)title;
/// A WebAuthn request (`create`, `get` or `available`) from a frame. `reply(ok, payload)`: the response JSON,
/// or `"ErrorName|message"`.
- (void)chromiumPage:(NRAChromiumPage *)page
            webAuthn:(NSString *)kind
                json:(NSString *)json
            frameURL:(NSString *)frameURL
              topURL:(NSString *)topURL
               reply:(void (^)(BOOL ok, NSString *payload))reply;
/// The page's favicon as PNG (at most 64 px, 2x).
- (void)chromiumPage:(NRAChromiumPage *)page favicon:(NSData *)png;
- (void)chromiumPage:(NRAChromiumPage *)page loading:(BOOL)loading canGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward;
- (void)chromiumPage:(NRAChromiumPage *)page progress:(double)progress;
/// `reply` may be called later, once. If it is released uncalled, the dialog is cancelled.
- (void)chromiumPage:(NRAChromiumPage *)page
              dialog:(NRADialogKind)kind
           originURL:(NSString *)originURL
             message:(NSString *)message
         defaultText:(NSString *)defaultText
               reply:(void (^)(BOOL ok, NSString *_Nullable text))reply;
/// A site asks for permissions. `reply` once; if it's released uncalled, the request is denied.
- (void)chromiumPage:(NRAChromiumPage *)page
    permissionRequestFromOrigin:(NSString *)origin
                          kinds:(NRAPermissionKinds)kinds
                          reply:(void (^)(BOOL granted))reply;
/// `reply` with a file path to save, or nil to cancel. If it is released uncalled, CEF cancels.
- (void)chromiumPage:(NRAChromiumPage *)page
    downloadRequested:(uint32_t)downloadID
                  url:(NSString *)url
        suggestedName:(NSString *)suggestedName
             mimeType:(NSString *)mimeType
           totalBytes:(int64_t)totalBytes
                reply:(void (^)(NSString *_Nullable path))reply;
- (void)chromiumPage:(NRAChromiumPage *)page
            download:(uint32_t)downloadID
            received:(int64_t)received
               total:(int64_t)total
            complete:(BOOL)complete
            canceled:(BOOL)canceled
         interrupted:(BOOL)interrupted
                path:(NSString *)path;
- (void)chromiumPage:(NRAChromiumPage *)page findMatches:(int)count active:(int)active isFinal:(BOOL)isFinal;
- (void)chromiumPage:(NRAChromiumPage *)page processTerminated:(NRATermination)reason;
@end

/// One browser (Alloy style, child of `view`). Created synchronously, so every method works at once.
@interface NRAChromiumPage : NSObject
/// `storageKey` selects the request context: pages with the same key share cookies and storage.
/// Persistent contexts live under the root cache path; ephemeral ones are memory-only.
/// `passkeys`: whether pages may see `PublicKeyCredential` (an authenticator is available). WebAuthn calls are
/// always routed through Nera either way, so they never hang.
- (instancetype)initWithStorageKey:(NSString *)storageKey
                        persistent:(BOOL)persistent
                          passkeys:(BOOL)passkeys
                          delegate:(id<NRAChromiumPageDelegate>)delegate;
- (instancetype)init NS_UNAVAILABLE;
/// The view Chromium renders into. Resizes with its superview.
@property(nonatomic, readonly) NSView *view;
- (void)loadURL:(NSString *)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stop;
/// 1.0 = 100%.
- (void)setZoomFactor:(double)factor;
- (void)setMuted:(BOOL)muted;
/// Results arrive through `chromiumPage:findMatches:active:isFinal:`.
- (void)find:(NSString *)text forward:(BOOL)forward matchCase:(BOOL)matchCase findNext:(BOOL)findNext;
- (void)stopFinding;
- (void)startDownload:(NSString *)url;
/// Cancels a running download.
- (void)cancelDownload:(uint32_t)downloadID;
/// Adds or removes "Inspect Element" in the context menu; `showDevTools` works only while enabled.
- (void)setDevToolsEnabled:(BOOL)enabled;
/// Opens DevTools in their own window.
- (void)showDevTools;
/// Runs one of Nera's scripts in the top frame (through the renderer helper) and calls back on the main thread
/// with its result as a string (objects as JSON), or nil if it failed.
- (void)evaluate:(NSString *)script completion:(void (^)(NSString *_Nullable result))completion;
/// Closes the browser. No delegate callbacks after this returns.
- (void)close;
/// Deletes cookies and cached data of one request context.
+ (void)removeDataForStorageKey:(NSString *)storageKey persistent:(BOOL)persistent completion:(void (^)(void))completion;
/// Adds cookies to one request context (sign-ins imported from another browser). Each dictionary has
/// domain, name, value, path (strings), secure, httpOnly (NSNumber bools), and optionally expires (NSNumber,
/// seconds since 1970) and sameSite ("None", "Lax", "Strict"). Calls back on the main thread with how many
/// Chromium accepted.
+ (void)setCookies:(NSArray<NSDictionary<NSString *, id> *> *)cookies
     forStorageKey:(NSString *)storageKey
        persistent:(BOOL)persistent
        completion:(void (^)(NSInteger added))completion;
/// The cookies of one site (`site` and its subdomains) in one request context, in the same dictionary form as
/// ``setCookies:forStorageKey:persistent:completion:``: for moving a tab to the other engine signed in. Calls back
/// on the main thread (an empty array if Chromium isn't running).
+ (void)cookiesForSite:(NSString *)site
         storageKey:(NSString *)storageKey
         persistent:(BOOL)persistent
         completion:(void (^)(NSArray<NSDictionary<NSString *, id> *> *cookies))completion;
@end

NS_ASSUME_NONNULL_END
