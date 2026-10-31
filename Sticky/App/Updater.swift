import AppKit

/// Checks GitHub Releases for a newer Sticky and installs it in place:
/// download Sticky.zip, unzip, check it's really Sticky, then a small script
/// swaps the app bundle once we've quit and relaunches it.
@MainActor
final class Updater {
    static let shared = Updater()

    private let latestReleaseURL = URL(string: "https://api.github.com/repos/harit-gillar/Sticky/releases/latest")!
    private let releasesPageURL = URL(string: "https://github.com/harit-gillar/Sticky/releases")!
    private let lastCheckKey = "updater_lastCheck"
    private var isBusy = false

    struct Release {
        let version: String
        let notes: String
        let zipURL: URL
        let pageURL: URL
    }

    enum UpdateError: LocalizedError {
        case badResponse
        case noZip
        case unzipFailed
        case notSticky

        var errorDescription: String? {
            switch self {
            case .badResponse: return "GitHub didn't send back a release."
            case .noZip:       return "The latest release has no Sticky.zip to download."
            case .unzipFailed: return "The download couldn't be unzipped."
            case .notSticky:   return "The download doesn't contain a matching Sticky.app."
            }
        }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: - Checking

    /// Quiet check, at most once a day. Only speaks up when there's an update.
    func checkInBackgroundIfDue() {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 24 * 60 * 60 else { return }
        Task { await check(userInitiated: false) }
    }

    /// Sticky ▸ Check for Updates…
    func checkNow() {
        Task { await check(userInitiated: true) }
    }

    private func check(userInitiated: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let release: Release
        do {
            release = try await fetchLatestRelease()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        } catch {
            if userInitiated {
                showAlert("Couldn't check for updates", error.localizedDescription)
            }
            return
        }

        guard Self.isVersion(release.version, newerThan: currentVersion) else {
            if userInitiated {
                showAlert("You're up to date", "Sticky \(currentVersion) is the latest version.")
            }
            return
        }

        if askToInstall(release) {
            await install(release)
        }
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { throw UpdateError.badResponse }

        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let zip = assets.first(where: { ($0["name"] as? String) == "Sticky.zip" }),
              let zipString = zip["browser_download_url"] as? String,
              let zipURL = URL(string: zipString) else { throw UpdateError.noZip }

        let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPageURL
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, notes: json["body"] as? String ?? "", zipURL: zipURL, pageURL: page)
    }

    /// Numeric compare of dotted versions: 1.10.0 > 1.9.2, 1.2 == 1.2.0
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Installing

    private func askToInstall(_ release: Release) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Sticky \(release.version) is available"
        var info = "You have \(currentVersion). Sticky will quit, update and reopen."
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            info += "\n\n" + (notes.count > 600 ? String(notes.prefix(600)) + "…" : notes)
        }
        alert.informativeText = info
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Release Notes")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return true
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(release.pageURL)
            return false
        default:
            return false
        }
    }

    private func install(_ release: Release) async {
        let appURL = Bundle.main.bundleURL
        let fm = FileManager.default

        // Running from a read-only or translocated spot (e.g. straight out of
        // Downloads): we can't swap ourselves, so send them to the download.
        guard !appURL.path.contains("/AppTranslocation/"),
              fm.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            showAlert(
                "Sticky can't update itself here",
                "Move Sticky into your Applications folder, then check again. Opening the download page instead."
            )
            NSWorkspace.shared.open(release.pageURL)
            return
        }

        do {
            let work = fm.temporaryDirectory.appendingPathComponent("StickyUpdate-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: work, withIntermediateDirectories: true)

            let (downloaded, response) = try await URLSession.shared.download(from: release.zipURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.badResponse }
            let zipURL = work.appendingPathComponent("Sticky.zip")
            try fm.moveItem(at: downloaded, to: zipURL)

            let unzipped = work.appendingPathComponent("unzipped", isDirectory: true)
            guard try await run("/usr/bin/ditto", ["-x", "-k", zipURL.path, unzipped.path]) == 0 else {
                throw UpdateError.unzipFailed
            }

            let contents = try fm.contentsOfDirectory(at: unzipped, includingPropertiesForKeys: nil)
            guard let newApp = contents.first(where: { $0.pathExtension == "app" }),
                  let newBundle = Bundle(url: newApp),
                  newBundle.bundleIdentifier == Bundle.main.bundleIdentifier else { throw UpdateError.notSticky }

            try launchSwapScript(oldApp: appURL, newApp: newApp, work: work)
            StickyStore.shared.saveToDisk()
            NSApp.terminate(nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Update failed"
            alert.informativeText = "\(error.localizedDescription)\n\nYou can download it yourself from GitHub."
            alert.addButton(withTitle: "Open Download Page")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.pageURL)
            }
        }
    }

    /// Waits for this process to exit, swaps the bundle (restoring the old one
    /// if the copy fails), then reopens Sticky. Paths go in as arguments so
    /// spaces and quotes can't break the script.
    private func launchSwapScript(oldApp: URL, newApp: URL, work: URL) throws {
        let script = """
        pid="$1"; old="$2"; new="$3"; work="$4"
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        backup="$work/previous.app"
        mv "$old" "$backup" || { open "$old"; exit 1; }
        if ditto "$new" "$old"; then
            xattr -dr com.apple.quarantine "$old" 2>/dev/null
            open "$old"
            rm -rf "$work"
        else
            rm -rf "$old"
            mv "$backup" "$old"
            open "$old"
        fi
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sticky-update",
                             String(ProcessInfo.processInfo.processIdentifier),
                             oldApp.path, newApp.path, work.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private func run(_ tool: String, _ args: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = args
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
