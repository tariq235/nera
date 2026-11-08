// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

public import Foundation

/// Writes conformance reports to `<repo>/build/conformance/<engine>.json`, where
/// `scripts/ci/render-engine-matrix.py` turns them into the parity matrix in checklist 005.
public enum ConformanceReportWriter {
    /// The repository root, derived from this source file's location.
    static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }  // …/Packages/NeraKit/Sources/EngineConformance/<file>
        return url
    }

    /// Saves `report` as pretty-printed JSON and returns the file URL.
    @discardableResult
    public static func write(_ report: ConformanceReport) throws -> URL {
        let dir = repositoryRoot.appending(path: "build/conformance", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "\(report.engineID).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: file, options: .atomic)
        return file
    }
}
