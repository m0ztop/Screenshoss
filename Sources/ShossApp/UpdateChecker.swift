import Foundation

struct ScreenshossRelease: Sendable {
    let version: String
    let pageURL: URL
    let downloadURL: URL
}

enum UpdateCheckError: LocalizedError {
    case invalidResponse
    case noPublishedRelease

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "GitHub returned an invalid update response. Try again later."
        case .noPublishedRelease:
            "No published Screenshoss update is available yet."
        }
    }
}

struct UpdateChecker {
    private struct ReleaseResponse: Decodable, Sendable {
        struct Asset: Decodable, Sendable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/m0ztop/Screenshoss/releases/latest"
    )!

    static func fetchLatestRelease() async throws -> ScreenshossRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Screenshoss-Update-Checker", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }
        if httpResponse.statusCode == 404 {
            throw UpdateCheckError.noPublishedRelease
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw UpdateCheckError.invalidResponse
        }

        let release = try JSONDecoder().decode(ReleaseResponse.self, from: data)
        let downloadURL = release.assets.first {
            $0.name.caseInsensitiveCompare("Screenshoss.dmg") == .orderedSame
        }?.browserDownloadURL ?? release.htmlURL

        return ScreenshossRelease(
            version: normalizedVersion(release.tagName),
            pageURL: release.htmlURL,
            downloadURL: downloadURL
        )
    }

    static func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        let candidateParts = versionComponents(candidate)
        let currentParts = versionComponents(current)
        let componentCount = max(candidateParts.count, currentParts.count)

        for index in 0..<componentCount {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            if candidatePart != currentPart {
                return candidatePart > currentPart
            }
        }
        return false
    }

    static func normalizedVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private static func versionComponents(_ version: String) -> [Int] {
        normalizedVersion(version)
            .split(separator: ".")
            .map { component in
                let digits = component.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }
}
