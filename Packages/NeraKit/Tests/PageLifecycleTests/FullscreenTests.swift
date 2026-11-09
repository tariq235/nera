// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineKit
import Testing

@testable import PageLifecycle

/// A page's HTML full screen (a video's full-screen button): the window shows that page alone until it leaves.
@MainActor
struct FullscreenTests {
    @Test func aPageEnteringFullScreenIsRecordedUntilItLeavesOrGoesAway() {
        let f = Fixture()
        let a = f.tab()
        let page = f.show(a)
        page.simulate(.fullscreenChanged(true))
        #expect(f.manager.fullscreenPageID == a.id)
        page.simulate(.fullscreenChanged(false))
        #expect(f.manager.fullscreenPageID == nil)
        page.simulate(.fullscreenChanged(true))
        f.manager.discard(a.id)
        #expect(f.manager.fullscreenPageID == nil, "a page that's gone can't keep the window full screen")
    }

    @Test func anotherPageLeavingDoesNotEndThisOnesFullScreen() {
        let f = Fixture()
        let a = f.tab()
        let b = f.tab("https://b.example")
        let pa = f.show(a)
        let pb = f.show(b)
        pa.simulate(.fullscreenChanged(true))
        pb.simulate(.fullscreenChanged(false))
        #expect(f.manager.fullscreenPageID == a.id)
    }
}
