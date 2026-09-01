import Foundation

/// A dotted numeric version, compared component by component.
///
/// Release tags carry a `v` prefix (`v2.2`) while `CFBundleShortVersionString`
/// does not (`2.2`), so the prefix is stripped before parsing. Components are
/// compared as numbers, which is what makes 2.10 sort above 2.9 — a plain
/// string comparison gets that backwards.
struct AppVersion: Comparable {

    private let components: [Int]

    init?(_ string: String) {
        let stripped = string.trimmingCharacters(in: .whitespaces)
            .drop { $0 == "v" || $0 == "V" }
        let parts = stripped.split(separator: ".")
        guard !parts.isEmpty else { return nil }

        var parsed: [Int] = []
        for part in parts {
            // Tolerate a trailing qualifier like "2.3-beta1" by taking only the
            // leading digits of each component.
            guard let value = Int(part.prefix { $0.isNumber }) else { return nil }
            parsed.append(value)
        }
        components = parsed
    }

    /// The running app's version, read back from its own bundle.
    static var current: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .flatMap(AppVersion.init)
    }

    /// Missing trailing components count as zero, so `2.2` == `2.2.0`.
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left  = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// Notices when a newer release has been published on GitHub.
///
/// Check-only by design: this type never downloads or replaces anything
/// itself. It reports what's available — including the release's DMG, when it
/// carries one — and `UpdateInstaller` acts on that. Keeping the roles split
/// keeps releasing to `./release.sh` plus `gh release create`: the release's
/// own DMG asset is the update feed, so there is no appcast to host and no
/// second signing key to keep in step with the first.
///
/// Every failure path is silent. No network, a rate limit, or a payload we
/// can't parse should never surface an error in a menu that exists to control
/// cooling — the check simply retries tomorrow.
final class UpdateChecker {

    /// A release newer than the running build, once one has been seen.
    struct Available {
        /// The release tag, e.g. `v2.3`. This is the identity used for skipping,
        /// so re-tagging a release offers it again.
        let tag: String
        /// The release page, which carries both the notes and the DMG.
        let page: URL
        /// Direct download for the release's DMG asset, when it has one.
        /// `nil` — a release published without a DMG — falls back to the old
        /// behaviour: the banner opens `page` instead of installing.
        let dmgURL: URL?

        /// The tag without its `v`, for display: `2.3`.
        var displayVersion: String { String(tag.drop { $0 == "v" || $0 == "V" }) }
    }

    private(set) var available: Available?

    /// Called on the main queue whenever `available` changes, so the menu can
    /// show or hide its banner without polling for it.
    var onChange: (() -> Void)?

    private let session: URLSession
    private var isChecking = false

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Config.Updates.requestTimeout
        // Never queue the request waiting for a network that isn't there; a
        // missed check costs nothing, a stalled one holds a socket for hours.
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    // ── Checking ─────────────────────────────────────────────────────────────

    /// Runs a check only if the interval has elapsed since the last one.
    ///
    /// Safe to call often — from the tick, say. Launch calls `check()` directly
    /// instead; this exists so an app left running for days still notices a
    /// release without polling GitHub once a second.
    func checkIfDue() {
        let last = UserDefaults.standard.double(forKey: Config.Key.lastUpdateCheck)
        guard Date().timeIntervalSince1970 - last >= Config.Updates.checkInterval else { return }
        check()
    }

    /// Fetches the latest release, publishing it only if it is newer than the
    /// running build and hasn't been skipped.
    func check() {
        guard !isChecking, let current = AppVersion.current else { return }
        isChecking = true

        // Stamp the attempt, not the success: a repeatedly failing check (no
        // network, rate limited) must still back off rather than retry each tick.
        UserDefaults.standard.set(Date().timeIntervalSince1970,
                                  forKey: Config.Key.lastUpdateCheck)

        var request = URLRequest(url: Config.Updates.latestReleaseAPI)
        // GitHub rejects API requests that don't identify themselves.
        request.setValue("RedMagic-Cooler", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        session.dataTask(with: request) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                self?.finish(data: data, response: response, current: current)
            }
        }.resume()
    }

    private func finish(data: Data?, response: URLResponse?, current: AppVersion) {
        isChecking = false

        guard let data,
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data),
              let latest = AppVersion(release.tagName),
              latest > current
        else { return }

        guard UserDefaults.standard.string(forKey: Config.Key.skippedVersion) != release.tagName
        else { return }

        let dmg = release.assets
            .first { $0.name.lowercased().hasSuffix(".dmg") }
            .flatMap { URL(string: $0.downloadURL) }
        available = Available(tag: release.tagName,
                              page: URL(string: release.htmlURL) ?? Config.Updates.releasesPage,
                              dmgURL: dmg)
        EventLogger.record("update available: \(release.tagName)")
        onChange?()
    }

    // ── Skipping ─────────────────────────────────────────────────────────────

    /// Suppresses the notice for the release currently on offer. A later, higher
    /// release still shows, because the skip is keyed on this exact tag.
    func skipAvailable() {
        guard let available else { return }
        UserDefaults.standard.set(available.tag, forKey: Config.Key.skippedVersion)
        EventLogger.record("update skipped: \(available.tag)")
        self.available = nil
        onChange?()
    }

    // ── Payload ──────────────────────────────────────────────────────────────

    /// The fields we need out of GitHub's release JSON.
    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let downloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case downloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }
}
