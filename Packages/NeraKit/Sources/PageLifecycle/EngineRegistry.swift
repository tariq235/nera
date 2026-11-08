// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import BrowserCore
public import EngineKit
public import Foundation

/// The engines compiled into this app, in order of preference.
///
/// The app target (composition root) builds the registry: on macOS `[ChromiumEngine(), WebKitEngine()]`,
/// on iOS `[WebKitEngine()]`. Everything else asks the registry, so no UI or business logic ever names
/// a concrete engine (AP-1). An engine whose descriptor says `isAvailable == false` is skipped, which is
/// how Chromium can be listed first today and take over automatically once it ships.
@MainActor
public final class EngineRegistry {
    /// All engines, most preferred first.
    public let engines: [any BrowserEngine]

    /// Creates a registry. `engines` must not be empty.
    public init(_ engines: [any BrowserEngine]) {
        precondition(!engines.isEmpty, "EngineRegistry needs at least one engine")
        self.engines = engines
    }

    /// Engines that can run on this build.
    public var availableEngines: [any BrowserEngine] { engines.filter(\.descriptor.isAvailable) }

    /// The platform default: the first available engine.
    public var defaultEngine: any BrowserEngine { availableEngines.first ?? engines[0] }

    /// The engine for a page of `url` in `profile`: the site's engine (`SiteEngines`) when it's available,
    /// otherwise the profile's.
    public func engine(for profile: Profile, url: URL?) -> any BrowserEngine {
        if let wanted = SiteEngines.preferred(for: url, in: profile),
            let match = availableEngines.first(where: { $0.descriptor.id == wanted.rawValue })
        {
            return match
        }
        return engine(for: profile)
    }

    /// The engine a profile uses: its explicit choice if available, otherwise the platform default.
    public func engine(for profile: Profile) -> any BrowserEngine {
        if let wanted = profile.engine,
            let match = availableEngines.first(where: { $0.descriptor.id == wanted.rawValue })
        {
            return match
        }
        return defaultEngine
    }
}
