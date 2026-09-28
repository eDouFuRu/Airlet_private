import AppKit
import CryptoKit
import Defaults
import Foundation

/// Airlet releases are checked against our public GitHub repository, never the upstream
/// boring.notch appcast. A downloaded DMG is only staged; installation is manual.
@MainActor
final class AirletUpdateService: ObservableObject {
    static let shared = AirletUpdateService()
    static let repositoryURL = URL(string: "https://github.com/eDouFuRu/notch-island")!
    private static let latestURL = URL(string: "https://api.github.com/repos/eDouFuRu/notch-island/releases/latest")!

    @Published private(set) var isChecking = false
    @Published private(set) var status = ""
    @Published private(set) var releaseURL: URL?
    @Published private(set) var downloadedURL: URL?
    private var pollingTask: Task<Void, Never>?

    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
        let assets: [Asset]
    }
    private struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let size: Int64
        let digest: String?
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                if Defaults[.automaticallyCheckAirletUpdates] { await self?.check() }
                try? await Task.sleep(for: .seconds(24 * 3600))
            }
        }
    }

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            var request = URLRequest(url: Self.latestURL, cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Airlet-update-check", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
            if http.statusCode == 404 {
                status = L("暂无可用的 Airlet 发布版本")
                return
            }
            guard http.statusCode == 200 else { throw UpdateError.invalidResponse }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            // Requiring the exact Airlet filename prevents legacy releases of this fork
            // (or an upstream boring.notch package) from being offered as an update.
            guard let asset = release.assets.first(where: { $0.name == "Airlet-\(version).dmg"
                && $0.browser_download_url.scheme == "https"
                && $0.browser_download_url.host == "github.com"
                && $0.size > 0 && $0.size < 500_000_000 }) else {
                status = L("暂无可用的 Airlet 发布版本")
                return
            }
            guard Self.isNewer(version, than: Bundle.main.releaseVersionNumber ?? "0") else {
                status = L("当前已是最新版本")
                releaseURL = nil
                return
            }
            releaseURL = release.html_url
            if Defaults[.automaticallyDownloadAirletUpdates] {
                try await download(asset)
                status = String(format: L("已下载 Airlet %@，请手动安装"), version)
            } else {
                status = String(format: L("发现 Airlet %@ 新版本"), version)
            }
        } catch {
            status = L("检查更新失败，请稍后重试")
        }
    }

    private func download(_ asset: Asset) async throws {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
            .appendingPathComponent("Airlet/Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(asset.name)
        if FileManager.default.fileExists(atPath: destination.path) {
            if (try? verifyFile(destination, asset: asset)) == true {
                downloadedURL = destination
                return
            }
            try FileManager.default.removeItem(at: destination)
        }
        let (temporary, response) = try await URLSession.shared.download(from: asset.browser_download_url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.invalidResponse
        }
        guard try verifyFile(temporary, asset: asset) else { throw UpdateError.invalidResponse }
        try FileManager.default.moveItem(at: temporary, to: destination)
        downloadedURL = destination
    }

    private func verifyFile(_ url: URL, asset: Asset) throws -> Bool {
        let length = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        guard length?.int64Value == asset.size else { return false }
        guard let digest = asset.digest, digest.hasPrefix("sha256:") else { return true }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        return actual.caseInsensitiveCompare(String(digest.dropFirst(7))) == .orderedSame
    }

    private enum UpdateError: Error { case invalidResponse }

    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        func components(_ version: String) -> [Int]? {
            let parts = version.split(separator: ".", omittingEmptySubsequences: false)
            guard !parts.isEmpty, parts.count <= 4 else { return nil }
            let values = parts.compactMap { Int($0) }
            return values.count == parts.count ? values : nil
        }
        guard let newer = components(candidate), let current = components(installed) else { return false }
        for index in 0..<max(newer.count, current.count) {
            let a = index < newer.count ? newer[index] : 0
            let b = index < current.count ? current[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}
