// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import EngineTestSupport
import Foundation
import TestSupport
import Testing

@testable import Import

/// Importer fuzzing (SEC-067): a damaged or hostile Arc file never crashes Nera.
@Suite("Arc importer fuzz")
struct ArcImporterFuzzTests {
    @Test func damagedSidebarFilesParseOrFailCleanly() throws {
        let url = try #require(Bundle.module.url(forResource: "StorableSidebar.sample", withExtension: "json", subdirectory: "Fixtures"))
        let sample = try Data(contentsOf: url)
        var parsed = 0
        for seed in UInt64(0)..<1500 * SeededRandom.scale {
            var rng = SeededRandom(seed: seed)
            if let result = try? ArcImporter.parse(data: rng.mutate(sample), profileID: UUID()) {
                parsed += 1
                for space in result.spaces { _ = (space.pinned + space.today).flatMap(\.tabs) }
            }
        }
        #expect(parsed > 0, "sanity: some mutations still parse")
    }

    @Test func wrongShapesAreRejected() {
        let shapes = [
            #"[]"#, #"{"sidebar":1}"#, #"{"sidebar":{"containers":[{"spaces":5,"items":"x"}]}}"#, "null",
            #"{"sidebar":{"containers":[null]}}"#,
        ]
        for shape in shapes {
            _ = try? ArcImporter.parse(data: Data(shape.utf8), profileID: UUID())
        }
    }
}
