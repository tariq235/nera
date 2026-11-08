// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Nera's CEF bridge: process-wide lifecycle. Part of the ChromiumEngine adapter (ADR-0010); the only
// place outside ChromiumEngine that knows about CEF. No CEF types cross this header.
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The NSApplication subclass CEF requires on macOS (implements CefAppProtocol). Set as NSPrincipalClass.
/// Harmless when Chromium isn't started.
@interface NRAChromiumApplication : NSApplication
@end

/// CEF lifecycle.
/// Posted (main thread) when an assistive app appears after Chromium started without page accessibility: Nera
/// offers to restart (A11Y-009). Same name as `WebAccessibility.needsRestart` in BrowserShell.
extern NSNotificationName const NRAChromiumAccessibilityNeedsRestart;

@interface NRAChromium : NSObject
/// Loads the framework and initializes CEF with an external message pump on the AppKit run loop.
/// `cachePath` is the root of all Chromium profile data; `keychainService` names Nera's own Keychain
/// item for cookie encryption (never the shared "Chromium Safe Storage"; SEC-073).
/// `mockKeychain` (automated tests only): no real Keychain item, so ad-hoc-signed test builds never trigger
/// Keychain prompts. Nera's configured item is still reported by `keychainService`.
/// `extensionPaths`: unpacked, verified extension folders to load (Nera's extension manager); empty for none.
+ (BOOL)startWithCachePath:(NSString *)cachePath
           keychainService:(NSString *)keychainService
              mockKeychain:(BOOL)mockKeychain
            extensionPaths:(NSArray<NSString *> *)extensionPaths
         extensionsProfile:(nullable NSString *)extensionsProfile;
/// Debug test runs only (call before start): trust certificates with this SPKI SHA-256 (base64), i.e. the
/// local test server's valid certificate. Ignored in Release builds, where the switch is always stripped.
+ (void)setTestCertificateSPKI:(NSString *)spki;
/// Whether `start…` succeeded.
@property(class, nonatomic, readonly) BOOL isStarted;
/// Whether Chromium started with page accessibility: VoiceOver or Switch Control was on, or the
/// "NeraWebAccessibility" setting asked for it.
@property(class, nonatomic, readonly) BOOL isAccessibilityOn;
/// Runs `block` once Chromium has started (at once if it already has). Nera starts Chromium just after its first
/// window is on screen, so pages asked for before then wait here instead of falling back to WebKit. Dropped if
/// Chromium fails to start.
+ (void)whenStarted:(dispatch_block_t)block;
/// Runs `block` if Chromium fails to start (so waiting callers can answer), never if it starts.
+ (void)ifStartFails:(dispatch_block_t)block;
/// Closes every browser and shuts CEF down.
+ (void)shutdown;
/// Switch names on Chromium's effective (global) command line, for security checks (SEC-026).
+ (NSArray<NSString *> *)commandLineSwitches;
/// The Keychain service name CEF was configured with (SEC-073); nil before start.
@property(class, nonatomic, readonly, nullable) NSString *keychainService;
/// e.g. "CEF 156.0.15+gcf671c0 / Chromium 156.0.8078.80".
+ (NSString *)versionString;
@end

NS_ASSUME_NONNULL_END
