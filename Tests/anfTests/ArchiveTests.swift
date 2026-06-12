import Foundation
@testable import anf

/// Archive classification + real extraction through the built-in tools
/// (ditto / bsdtar). Covers zip, tar.gz (compound ext) and 7z — all of which
/// macOS handles with no extra install.
func runArchiveTests() {
    MainActor.assumeIsolated {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("anfarc-\(UUID().uuidString)")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let src = dir.appendingPathComponent("payload.txt")
        try? "anf archive test".write(to: src, atomically: true, encoding: .utf8)

        T.group("ArchiveService.kind classification") {
            func k(_ name: String) -> ArchiveService.Kind? {
                ArchiveService.kind(for: URL(fileURLWithPath: "/x/\(name)"))
            }
            T.expect(k("a.zip") == .zip, "zip → ditto")
            T.expect(k("a.tar.gz") == .libarchive, "compound tar.gz → bsdtar")
            T.expect(k("a.tgz") == .libarchive, "tgz → bsdtar")
            T.expect(k("a.7z") == .libarchive, "7z → bsdtar")
            T.expect(k("a.tar.xz") == .libarchive, "tar.xz → bsdtar")
            T.expect(k("a.rar") == .needsUnar, "rar → unar")
            T.expect(k("a.alz") == .needsUnar, "alz(한국) → unar")
            T.expect(k("a.txt") == nil, "plain file → not an archive")
        }

        // Helper: run a sync command, wait, return success.
        @discardableResult
        func sh(_ exe: String, _ args: [String], cwd: URL? = nil) -> Bool {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            if let cwd { p.currentDirectoryURL = cwd }
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 }
            catch { return false }
        }

        @MainActor func extractAndCheck(_ archive: URL, label: String) {
            var done = false
            ArchiveService.extract(FileItem(url: archive)!) { done = true }
            let deadline = Date().addingTimeInterval(15)
            while !done && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            // The extracted folder is named after the archive base, next to it.
            let out = archive.deletingLastPathComponent()
            let found = (try? fm.subpathsOfDirectory(atPath: out.path)) ?? []
            T.expect(found.contains { $0.hasSuffix("payload.txt") },
                     "\(label): payload.txt recovered from the archive")
        }

        T.group("Extract: zip (ditto)") {
            let zip = dir.appendingPathComponent("z.zip")
            T.expect(sh("/usr/bin/ditto", ["-c", "-k", src.path, zip.path]), "zip created")
            extractAndCheck(zip, label: "zip")
        }

        T.group("Extract: tar.gz (bsdtar, compound ext)") {
            let tgz = dir.appendingPathComponent("t.tar.gz")
            T.expect(sh("/usr/bin/tar", ["-czf", tgz.path, "payload.txt"], cwd: dir), "tar.gz created")
            extractAndCheck(tgz, label: "tar.gz")
        }

        T.group("Extract: 7z (bsdtar)") {
            let sevenz = dir.appendingPathComponent("s.7z")
            // bsdtar can WRITE 7z too, so we don't need p7zip to make the fixture.
            T.expect(sh("/usr/bin/bsdtar", ["-cf", sevenz.path, "--format", "7zip",
                                            "-C", dir.path, "payload.txt"]), "7z created")
            extractAndCheck(sevenz, label: "7z")
        }
    }
}
