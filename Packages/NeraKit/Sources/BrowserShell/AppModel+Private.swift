// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
public import PageLifecycle
import Storage

// Private windows.
extension AppModel {
    /// A model for one private window, sharing the main window's engines. Its pages share one ephemeral session
    /// that ends when the window closes (``closePrivateWindow()``).
    public static func privateWindow(registry: EngineRegistry) -> AppModel {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        let model = AppModel(store: .load(persistence: InMemoryStore()), registry: registry, downloadsDirectory: downloads)
        model.isPrivate = true
        model.pages.defaultStorage = .ephemeral(UUID())
        if let space = model.state.selectedSpace {
            model.send(.space(.rename(space.id, title: "Private")))
        }
        return model
    }

    /// Closes every page of a private window, ending its session.
    public func closePrivateWindow() {
        guard isPrivate else { return }
        pages.discardAll()
    }
}
