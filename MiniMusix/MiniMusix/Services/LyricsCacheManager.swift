import Foundation

final class LyricsCacheManager {
    private struct CacheKey: Hashable {
        var title: String
        var artist: String
        var duration: Int
    }

    private struct DiskEntry: Codable {
        enum PayloadKind: String, Codable {
            case synced
            case plain
            case instrumental
            case unavailable
        }

        var identity: TrackIdentity
        var fetchedDate: Date
        var kind: PayloadKind
        var syncedLines: [String]?
        var syncedTimes: [TimeInterval]?
        var plainLyrics: String?
        var sourceEndpoint: String?
    }

    private struct DiskStore: Codable {
        var entries: [DiskEntry]
    }

    private let foundTTL: TimeInterval = 30 * 24 * 60 * 60
    private let unavailableTTL: TimeInterval = 6 * 60 * 60
    private var storage: [CacheKey: DiskEntry] = [:]
    private let diskURL: URL?

    init() {
        let fileManager = FileManager.default
        if let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let directory = applicationSupportURL.appendingPathComponent("MiniMusix", isDirectory: true)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            self.diskURL = directory.appendingPathComponent("LyricsCache.json")
        } else {
            self.diskURL = nil
        }

        loadFromDisk()
    }

    subscript(identity: TrackIdentity) -> LyricsPayload? {
        get {
            let cacheKey = key(for: identity)
            guard let entry = storage[cacheKey] else {
                return nil
            }

            if isExpired(entry) {
                storage[cacheKey] = nil
                saveToDisk()
                return nil
            }

            if entry.kind == .unavailable {
                storage[cacheKey] = nil
                saveToDisk()
                return nil
            }

            return payload(from: entry)
        }
        set {
            let cacheKey = key(for: identity)
            guard let newValue else {
                storage[cacheKey] = nil
                saveToDisk()
                return
            }

            storage[cacheKey] = entry(for: identity, payload: newValue, sourceEndpoint: nil)
            saveToDisk()
        }
    }

    func store(_ payload: LyricsPayload, for identity: TrackIdentity, sourceEndpoint: String?) {
        guard payload != .loading else { return }
        guard payload != .unavailable else {
            storage[key(for: identity)] = nil
            saveToDisk()
            return
        }
        storage[key(for: identity)] = entry(for: identity, payload: payload, sourceEndpoint: sourceEndpoint)
        saveToDisk()
    }

    func clear() {
        storage.removeAll()
        saveToDisk()
    }

    private func entry(for identity: TrackIdentity, payload: LyricsPayload, sourceEndpoint: String?) -> DiskEntry {
        switch payload {
        case .loading:
            return DiskEntry(identity: identity, fetchedDate: Date(), kind: .unavailable, syncedLines: nil, syncedTimes: nil, plainLyrics: nil, sourceEndpoint: sourceEndpoint)
        case .synced(let lines):
            return DiskEntry(
                identity: identity,
                fetchedDate: Date(),
                kind: .synced,
                syncedLines: lines.map(\.text),
                syncedTimes: lines.map(\.time),
                plainLyrics: nil,
                sourceEndpoint: sourceEndpoint
            )
        case .plain(let text):
            return DiskEntry(
                identity: identity,
                fetchedDate: Date(),
                kind: text.isEmpty ? .instrumental : .plain,
                syncedLines: nil,
                syncedTimes: nil,
                plainLyrics: text,
                sourceEndpoint: sourceEndpoint
            )
        case .unavailable:
            return DiskEntry(identity: identity, fetchedDate: Date(), kind: .unavailable, syncedLines: nil, syncedTimes: nil, plainLyrics: nil, sourceEndpoint: sourceEndpoint)
        }
    }

    private func payload(from entry: DiskEntry) -> LyricsPayload {
        switch entry.kind {
        case .synced:
            let texts = entry.syncedLines ?? []
            let times = entry.syncedTimes ?? []
            let lines = zip(times, texts).map { SyncedLyricLine(time: $0.0, text: $0.1) }
            return lines.isEmpty ? .unavailable : .synced(lines)
        case .plain:
            return .plain(entry.plainLyrics ?? "")
        case .instrumental:
            return .plain("")
        case .unavailable:
            return .unavailable
        }
    }

    private func isExpired(_ entry: DiskEntry) -> Bool {
        let ttl = entry.kind == .unavailable ? unavailableTTL : foundTTL
        return Date().timeIntervalSince(entry.fetchedDate) > ttl
    }

    private func loadFromDisk() {
        guard let diskURL,
              let data = try? Data(contentsOf: diskURL),
              let diskStore = try? JSONDecoder().decode(DiskStore.self, from: data) else {
            return
        }

        var loadedStorage: [CacheKey: DiskEntry] = [:]
        for entry in diskStore.entries where !isExpired(entry) && entry.kind != .unavailable {
            let cacheKey = key(for: entry.identity)
            if let existing = loadedStorage[cacheKey],
               existing.fetchedDate > entry.fetchedDate {
                continue
            }
            loadedStorage[cacheKey] = entry
        }
        storage = loadedStorage
    }

    private func saveToDisk() {
        guard let diskURL else {
            return
        }

        let validEntries = storage.values.filter { !isExpired($0) }
        storage = Dictionary(uniqueKeysWithValues: validEntries.map { (key(for: $0.identity), $0) })

        guard let data = try? JSONEncoder().encode(DiskStore(entries: Array(storage.values))) else {
            return
        }

        try? data.write(to: diskURL, options: [.atomic])
    }

    private func key(for identity: TrackIdentity) -> CacheKey {
        CacheKey(
            title: normalizedMetadata(identity.title),
            artist: normalizedMetadata(identity.artist),
            duration: durationKey(identity.duration)
        )
    }

    private func normalizedMetadata(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func durationKey(_ duration: TimeInterval) -> Int {
        guard duration.isFinite, duration > 0 else { return 0 }
        return Int(duration.rounded())
    }
}
