// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Nera's CEF bridge: process-wide lifecycle (ADR-0006, ADR-0009, ADR-0010).
// Written for Nera against CEF's public API (include/*.h).
#import "NRAChromium.h"

#include <string>
#include <vector>

#import <objc/runtime.h>
#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_command_line.h"
#include "include/cef_preference.h"
#include "include/cef_request_context.h"
#include "include/cef_version.h"
#include "include/wrapper/cef_library_loader.h"

// MARK: - NSApplication subclass (CefAppProtocol)

@interface NRAChromiumApplication () <CefAppProtocol>
@end

@implementation NRAChromiumApplication {
    BOOL _handlingSendEvent;
}
- (BOOL)isHandlingSendEvent { return _handlingSendEvent; }
- (void)setHandlingSendEvent:(BOOL)handlingSendEvent { _handlingSendEvent = handlingSendEvent; }
- (void)sendEvent:(NSEvent *)event {
    CefScopedSendingEvent sendingEventScoper;
    [super sendEvent:event];
}
@end

/// SwiftUI runs its own NSApplication subclass and ignores NSPrincipalClass, so NRAChromiumApplication may not be
/// the running class. Chromium calls -isHandlingSendEvent on NSApp (an unrecognized selector crashed Nera,
/// found by the site check on 2026-10-29). Give the running class CefAppProtocol's behavior at runtime.
static BOOL gHandlingSendEvent = NO;
static void NRAEnsureCefAppProtocol(void) {
    Class cls = [NSApp class];
    if ([NSApp conformsToProtocol:@protocol(CefAppProtocol)] || [cls isSubclassOfClass:[NRAChromiumApplication class]]) return;
    class_addMethod(cls, @selector(isHandlingSendEvent), imp_implementationWithBlock(^BOOL(id) { return gHandlingSendEvent; }), "c@:");
    class_addMethod(cls, @selector(setHandlingSendEvent:),
                    imp_implementationWithBlock(^(id, BOOL handling) { gHandlingSendEvent = handling; }), "v@:c");
    // Wrap sendEvent: so Chromium knows when AppKit is dispatching an event (CefScopedSendingEvent's job).
    Method original = class_getInstanceMethod(cls, @selector(sendEvent:));
    IMP originalIMP = method_getImplementation(original);
    IMP wrapped = imp_implementationWithBlock(^(id app, NSEvent *event) {
        BOOL previous = gHandlingSendEvent;
        gHandlingSendEvent = YES;
        ((void (*)(id, SEL, NSEvent *))originalIMP)(app, @selector(sendEvent:), event);
        gHandlingSendEvent = previous;
    });
    if (!class_addMethod(cls, @selector(sendEvent:), wrapped, method_getTypeEncoding(original))) {
        method_setImplementation(class_getInstanceMethod(cls, @selector(sendEvent:)), wrapped);
    }
    class_addProtocol(cls, @protocol(CefAppProtocol));
}

// MARK: Assistive apps (A11Y-009)

NSNotificationName const NRAChromiumAccessibilityNeedsRestart = @"NeraWebAccessibilityNeedsRestart";

/// Whether Chromium started with page accessibility (VoiceOver, Voice Control, Switch Control can read pages).
static BOOL gAccessibility = NO;
/// The setting that asks for it on every start, set by Settings or once VoiceOver was seen.
static NSString *const kAccessibilityDefault = @"NeraWebAccessibility";

static void NRAAssistiveAppSeen(void) {
    if (gAccessibility) return;
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:kAccessibilityDefault];  // from the next start on
    static BOOL posted = NO;
    if (posted) return;
    posted = YES;
    [NSNotificationCenter.defaultCenter postNotificationName:NRAChromiumAccessibilityNeedsRestart object:nil];
}

/// Watches whether VoiceOver or Switch Control turns on during the session.
@interface NRAAssistiveObserver : NSObject
@end

@implementation NRAAssistiveObserver
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    NSWorkspace *workspace = NSWorkspace.sharedWorkspace;
    if (workspace.voiceOverEnabled || workspace.switchControlEnabled) NRAAssistiveAppSeen();
}
@end

/// Chromium can only make pages readable from its start, so an assistive app turning up later is remembered for the
/// next start and Nera offers to restart: VoiceOver or Switch Control switched on, or an assistive app setting
/// AXManualAccessibility on Nera (Chromium's explicit opt-in, as in Chrome and Electron). AXEnhancedUserInterface
/// isn't used: window managers set it too. Installed on whichever NSApplication class runs.
static void NRAInstallAccessibilityHooks(void) {
    static BOOL installed = NO;
    if (installed) return;
    installed = YES;
    NSWorkspace *workspace = NSWorkspace.sharedWorkspace;
    gAccessibility = workspace.voiceOverEnabled || workspace.switchControlEnabled ||
                     [NSUserDefaults.standardUserDefaults boolForKey:kAccessibilityDefault];
    static NRAAssistiveObserver *observer;
    observer = [NRAAssistiveObserver new];
    [workspace addObserver:observer forKeyPath:@"voiceOverEnabled" options:0 context:nil];
    [workspace addObserver:observer forKeyPath:@"switchControlEnabled" options:0 context:nil];

    Class cls = [NSApp class];
    // Wraps an instance method of the running class, calling the inherited one inside.
    auto wrap = [cls](SEL selector, id block) {
        Method method = class_getInstanceMethod(cls, selector);
        IMP wrapped = imp_implementationWithBlock(block);
        if (!class_addMethod(cls, selector, wrapped, method_getTypeEncoding(method))) method_setImplementation(method, wrapped);
    };
    IMP setValue = method_getImplementation(class_getInstanceMethod(cls, @selector(accessibilitySetValue:forAttribute:)));
    wrap(@selector(accessibilitySetValue:forAttribute:), ^(id app, id value, NSString *attribute) {
        if ([attribute isEqualToString:@"AXManualAccessibility"]) {  // Chromium's attribute; AppKit doesn't know it
            if ([value respondsToSelector:@selector(boolValue)] && [value boolValue]) NRAAssistiveAppSeen();
            return;
        }
        ((void (*)(id, SEL, id, NSString *))setValue)(app, @selector(accessibilitySetValue:forAttribute:), value, attribute);
    });
    IMP settable = method_getImplementation(class_getInstanceMethod(cls, @selector(accessibilityIsAttributeSettable:)));
    wrap(@selector(accessibilityIsAttributeSettable:), ^BOOL(id app, NSString *attribute) {
        if ([attribute isEqualToString:@"AXManualAccessibility"]) return YES;
        return ((BOOL(*)(id, SEL, NSString *))settable)(app, @selector(accessibilityIsAttributeSettable:), attribute);
    });
}

extern std::string gRootCachePath;
/// Storage key of the profile Chromium starts with; extensions run there. Read by NRAChromiumPage.mm.
std::string gExtensionsProfile;  // defined below

namespace {

CefScopedLibraryLoader *gLoader = nullptr;
bool gStarted = false;
NSMutableArray<dispatch_block_t> *gStartWaiters = nil;  // work waiting for CefInitialize
NSMutableArray<dispatch_block_t> *gFailureWaiters = nil;  // answers owed if CefInitialize fails
bool gStartFailed = false;

/// Start failed: queued work is dropped (it needs CEF) and callers waiting for an answer get one.
void AbandonStart() {
    gStartFailed = true;
    gStartWaiters = nil;
    NSArray<dispatch_block_t> *failures = [gFailureWaiters copy];
    gFailureWaiters = nil;
    for (dispatch_block_t block in failures) block();
}
bool gInWork = false;
NSTimer *gPumpTimer = nil;
std::string gArgv0;
NSString *gKeychainService = nil;
bool gMockKeychain = false;  // automated tests only
std::string gExtensionPaths;  // comma-separated unpacked extension folders
std::string gTestSPKI;       // Debug test runs only

/// Chromium services that call Google on their own even with the switches above, turned off through the same
/// preferences their enterprise policies set (found by the traffic audit, scripts/privacy/chromium-traffic.sh).
/// Browser-wide ones here; per-profile ones in ApplyProfilePrivacy (NRAChromiumPage.mm).
void ApplyGlobalPrivacy() {
    CefRefPtr<CefPreferenceManager> prefs = CefPreferenceManager::GetGlobalPreferenceManager();
    if (!prefs) return;
    CefString error;
    auto set = [&](const char *name, CefRefPtr<CefValue> value) {
        if (prefs->CanSetPreference(name)) prefs->SetPreference(name, value, error);
    };
    CefRefPtr<CefValue> no = CefValue::Create();
    no->SetBool(false);
    set("network_time.network_time_queries_enabled", no);      // clients2.google.com/time
    set("component_updates.component_updates_enabled", no);    // update.googleapis.com, edgedl.me.gvt1.com
    CefRefPtr<CefValue> off = CefValue::Create();
    off->SetString("off");
    set("dns_over_https.mode", off);  // resolve through macOS, like Safari, so the Mac's own DNS settings apply
    // Chromium's startup profile (always loaded) gets the per-profile setting too, once it's ready.
    CefRefPtr<CefRequestContext> global = CefRequestContext::GetGlobalContext();
    CefRefPtr<CefValue> aiOff = CefValue::Create();
    aiOff->SetInt(1);  // AIModeSettings policy: 1 = off (www.google.com/async/folae eligibility checks)
    if (global && global->CanSetPreference("omnibox.ai_mode_settings")) global->SetPreference("omnibox.ai_mode_settings", aiOff, error);
    if (global && global->CanSetPreference("translate.enabled")) global->SetPreference("translate.enabled", no, error);
}

void DoWork() {
    if (gInWork || !gStarted) return;
    gInWork = true;
    CefDoMessageLoopWork();
    gInWork = false;
}

/// Switches that stop Chromium's own background traffic to Google services (Nera is private by
/// construction: the network inventory in docs/security/security-model.md lists every host the app
/// contacts on its own). Appended for every process type.
const char *const kPrivacySwitches[] = {
    "disable-background-networking",  // variations, component updater pings, translate/ranker fetches
    "disable-component-update",       // Widevine/other component downloads (CEF updates ship with Nera)
    "disable-domain-reliability",     // Google reliability beacons
    "disable-sync",                   // no Google account sync
    "no-pings",                       // <a ping> auditing
    "disable-client-side-phishing-detection",  // model download; Safe Browsing is a separate decision (SIGN-010)
    "metrics-recording-only",         // never upload metrics
};

/// Switches that weaken security. Removed if anything tries to set them (ADR-0006).
const char *const kForbiddenSwitches[] = {
    "no-sandbox", "disable-web-security", "ignore-certificate-errors", "disable-site-isolation-trials",
    "allow-running-insecure-content", "remote-debugging-port", "remote-debugging-pipe", "single-process",
    "ignore-certificate-errors-spki-list", "user-data-dir", "host-resolver-rules",
};

class NeraApp : public CefApp, public CefBrowserProcessHandler {
   public:
    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }

    void OnBeforeCommandLineProcessing(const CefString &, CefRefPtr<CefCommandLine> commandLine) override {
        for (const char *name : kForbiddenSwitches) commandLine->RemoveSwitch(name);
        for (const char *name : kPrivacySwitches) commandLine->AppendSwitch(name);
        if (gMockKeychain) commandLine->AppendSwitch("use-mock-keychain");
        // Assistive apps (A11Y-009): Chromium builds pages' accessibility trees only with this switch. CEF's
        // per-browser SetAccessibilityState has no effect in Alloy style (CEF 156, verified), so it's decided at start.
        if (gAccessibility) commandLine->AppendSwitch("force-renderer-accessibility");
        // Extensions the user installed through Nera's extension manager (verified CRX3, unpacked by Nera).
        if (!gExtensionPaths.empty()) commandLine->AppendSwitchWithValue("load-extension", gExtensionPaths);
#if DEBUG
        // Debug test runs only: trust exactly the local test server's valid certificate (security conformance).
        if (!gTestSPKI.empty()) {
            commandLine->AppendSwitchWithValue("ignore-certificate-errors-spki-list", gTestSPKI);
            commandLine->AppendSwitchWithValue("user-data-dir", gRootCachePath);  // Chromium requires it for the list
            // S05 mixed content: a non-loopback name for the local test server (loopback isn't "mixed" in Chromium).
            commandLine->AppendSwitchWithValue("host-resolver-rules", "MAP *.nera.test 127.0.0.1");
        }
        // Debug privacy audits only (PRV-006, scripts/privacy/chromium-traffic.sh): Chromium logs every request it
        // makes to this file, so its own background traffic can be listed.
        if (const char *netlog = getenv("NERA_NETLOG")) commandLine->AppendSwitchWithValue("log-net-log", netlog);
        // Debug media checks only (how fast sound stops when a tab closes or Nera quits): pages play without a click.
        if (getenv("NERA_AUTOPLAY")) commandLine->AppendSwitchWithValue("autoplay-policy", "no-user-gesture-required");
#endif
    }

    /// CEF asks for work from any thread; hop to the main queue. A 30 Hz timer covers unannounced work.
    void OnScheduleMessagePumpWork(int64_t delayMs) override {
        if (delayMs <= 0) {
            dispatch_async(dispatch_get_main_queue(), ^{ DoWork(); });
        } else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delayMs * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ DoWork(); });
        }
    }

   private:
    IMPLEMENT_REFCOUNTING(NeraApp);
};

}  // namespace

/// Root of Chromium's profile data; read by NRAChromiumPage.mm for persistent request contexts.
std::string gRootCachePath;

@implementation NRAChromium

+ (BOOL)startWithCachePath:(NSString *)cachePath
           keychainService:(NSString *)keychainService
              mockKeychain:(BOOL)mockKeychain
            extensionPaths:(NSArray<NSString *> *)extensionPaths
         extensionsProfile:(nullable NSString *)extensionsProfile {
    if (gStarted) return YES;
    NRAEnsureCefAppProtocol();
    NRAInstallAccessibilityHooks();
    gLoader = new CefScopedLibraryLoader();
    if (!gLoader->LoadInMain()) {
        NSLog(@"Nera: failed to load the Chromium Embedded Framework");
        return NO;
    }
    // Only argv[0]: switches given on Nera's command line are never passed to Chromium, so nothing can
    // inject a forbidden switch from outside. Nera's own switches are added in OnBeforeCommandLineProcessing.
    gArgv0 = NSProcessInfo.processInfo.arguments.firstObject.UTF8String ?: "Nera";
    char *argv[] = {gArgv0.data()};
    CefMainArgs mainArgs(1, argv);

    // CEF compares each profile's cache_path with the *resolved* root (e.g. /var → /private/var). Give it the
    // resolved path, or every persistent profile silently falls back to in-memory storage.
    char resolved[PATH_MAX];
    if (realpath(cachePath.fileSystemRepresentation, resolved)) cachePath = [NSString stringWithUTF8String:resolved];

    CefSettings settings;
    settings.external_message_pump = true;  // AppKit (SwiftUI) owns the run loop
    settings.no_sandbox = false;            // every child process runs in Chromium's sandbox
    settings.persist_session_cookies = false;
    CefString(&settings.root_cache_path) = cachePath.UTF8String;
    // Chromium loads extensions into its startup profile only. Make that profile Nera's extensions profile
    // (its existing data folder), so installed extensions run there (NRAChromiumPage.mm ContextFor).
    gExtensionsProfile = extensionsProfile.UTF8String ?: "";
    NSString *startupProfile = gExtensionsProfile.empty()
        ? [cachePath stringByAppendingPathComponent:@"Default"]
        : [cachePath stringByAppendingPathComponent:[@"Profile-" stringByAppendingString:extensionsProfile]];
    CefString(&settings.cache_path) = startupProfile.UTF8String;
    CefString(&settings.keychain_service_name) = keychainService.UTF8String;
    gKeychainService = [keychainService copy];
    CefString(&settings.keychain_account_name) = "Nera";
#if DEBUG
    settings.log_severity = LOGSEVERITY_WARNING;
#else
    settings.log_severity = LOGSEVERITY_DISABLE;  // Chromium log lines can contain URLs (PRV-007)
#endif
    gRootCachePath = cachePath.UTF8String;

    gMockKeychain = mockKeychain;
    gExtensionPaths = [extensionPaths componentsJoinedByString:@","].UTF8String ?: "";
    if (!CefInitialize(mainArgs, settings, new NeraApp(), nullptr)) {
        NSLog(@"Nera: CefInitialize failed (%d)", CefGetExitCode());
        AbandonStart();
        return NO;
    }
    gStarted = true;
    gFailureWaiters = nil;
    ApplyGlobalPrivacy();
    NSArray<dispatch_block_t> *waiting = [gStartWaiters copy];
    gStartWaiters = nil;
    for (dispatch_block_t block in waiting) block();
    gPumpTimer = [NSTimer timerWithTimeInterval:1.0 / 30.0 repeats:YES block:^(NSTimer *) { DoWork(); }];
    [NSRunLoop.mainRunLoop addTimer:gPumpTimer forMode:NSRunLoopCommonModes];
    return YES;
}

+ (BOOL)isStarted { return gStarted; }
+ (BOOL)isAccessibilityOn { return gAccessibility; }

+ (void)ifStartFails:(dispatch_block_t)block {
    if (gStarted) return;
    if (gStartFailed) return block();
    if (!gFailureWaiters) gFailureWaiters = [NSMutableArray array];
    [gFailureWaiters addObject:[block copy]];
}

+ (void)whenStarted:(dispatch_block_t)block {
    if (gStarted) return block();
    if (gStartFailed) return;
    if (!gStartWaiters) gStartWaiters = [NSMutableArray array];
    [gStartWaiters addObject:[block copy]];
}

+ (void)setTestCertificateSPKI:(NSString *)spki {
#if DEBUG
    gTestSPKI = spki.UTF8String ?: "";
#endif
}

+ (NSArray<NSString *> *)commandLineSwitches {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    if (!gStarted) return names;  // CEF's library isn't loaded before start
    CefRefPtr<CefCommandLine> commandLine = CefCommandLine::GetGlobalCommandLine();
    if (!commandLine) return names;
    CefCommandLine::SwitchMap switches;
    commandLine->GetSwitches(switches);
    for (const auto &entry : switches) [names addObject:[NSString stringWithUTF8String:entry.first.ToString().c_str()]];
    return names;
}

+ (NSString *)keychainService { return gKeychainService; }

+ (void)shutdown {
    if (!gStarted) return;
    [gPumpTimer invalidate];
    gPumpTimer = nil;
    for (int i = 0; i < 20; i++) DoWork();  // let closing browsers finish
    gStarted = false;
    CefShutdown();
}

+ (NSString *)versionString {
    return [NSString stringWithFormat:@"CEF %s / Chromium %d.%d.%d.%d", CEF_VERSION, CHROME_VERSION_MAJOR, CHROME_VERSION_MINOR,
                                      CHROME_VERSION_BUILD, CHROME_VERSION_PATCH];
}

@end
