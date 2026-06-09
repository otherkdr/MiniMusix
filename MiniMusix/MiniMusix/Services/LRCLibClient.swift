import Foundation
import os

struct LRCLIBResponse: Decodable {
    let id: Int?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let syncedLyrics: String?
    let plainLyrics: String?
}

struct LRCLIBErrorResponse: Decodable {
    let code: Int?
    let name: String?
    let message: String?
}

final class LyricsFetchCoordinator {
    private struct FetchCandidate {
        var payload: LyricsPayload
        var sourceEndpoint: String
    }

    private struct TrackSignature {
        let trackName: String
        let artistName: String
        let albumName: String
        let duration: Int
    }

    private struct SearchStrategy {
        var queryItems: [URLQueryItem]
        var timeout: TimeInterval
    }

    private struct MatchIdentity {
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval
    }

    private let cache: LyricsCacheManager
    private let session: URLSession
    private let inFlightLock = NSLock()
    private let logger = Logger(subsystem: "MiniMusix", category: "LRCLIB")
    private let userAgent = "MiniMusix/1.0 (https://github.com/keder/minimusix)"
    private let fastRequestTimeout: TimeInterval = 1.8
    private let slowRequestTimeout: TimeInterval = 4.5
    private var inFlightFetches: [String: Task<FetchCandidate, Never>] = [:]

    init(cache: LyricsCacheManager = LyricsCacheManager(), session: URLSession? = nil) {
        self.cache = cache

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = fastRequestTimeout
            configuration.timeoutIntervalForResource = slowRequestTimeout
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.waitsForConnectivity = false
            configuration.httpMaximumConnectionsPerHost = 3
            self.session = URLSession(configuration: configuration)
        }
    }

    func lyrics(for track: NowPlayingTrack, settings: MiniMusixSettings) async -> LyricsPayload {
        if let cached = cache[track.identity] {
            return selectLyrics(cached, settings: settings)
        }

        guard settings.enableLRCLIB, !Task.isCancelled else {
            return .unavailable
        }

        let result = await fetchLyrics(for: track)

        guard !Task.isCancelled else {
            return .unavailable
        }

        cache.store(result.payload, for: track.identity, sourceEndpoint: result.sourceEndpoint)
        return selectLyrics(result.payload, settings: settings)
    }

    func clearCache() {
        cache.clear()
    }

    func storeCustomLyrics(_ payload: LyricsPayload, for identity: TrackIdentity) {
        cache.store(payload, for: identity, sourceEndpoint: "custom-lrc")
    }

    private func requestKey(for identity: TrackIdentity) -> String {
        [
            normalized(identity.title),
            normalized(identity.artist),
            String(Int(identity.duration.rounded()))
        ]
        .joined(separator: "\u{1F}")
    }

    private func fetchTask(for key: String) -> Task<FetchCandidate, Never>? {
        inFlightLock.lock()
        defer { inFlightLock.unlock() }
        return inFlightFetches[key]
    }

    private func setFetchTask(_ task: Task<FetchCandidate, Never>, for key: String) {
        inFlightLock.lock()
        inFlightFetches[key] = task
        inFlightLock.unlock()
    }

    private func clearFetchTask(for key: String) {
        inFlightLock.lock()
        inFlightFetches[key] = nil
        inFlightLock.unlock()
    }

    private func fetchLyrics(for track: NowPlayingTrack) async -> FetchCandidate {
        let inFlightKey = requestKey(for: track.identity)
        if let task = fetchTask(for: inFlightKey) {
            return await task.value
        }

        let task = Task { [self] in
            await fetchLyricsUncached(for: track)
        }
        setFetchTask(task, for: inFlightKey)
        let result = await task.value
        clearFetchTask(for: inFlightKey)
        return result
    }

    private func fetchLyricsUncached(for track: NowPlayingTrack) async -> FetchCandidate {
        let signature = makeSignature(for: track)

        if let fastResult = await fetchFastLyrics(for: track, signature: signature) {
            return fastResult
        }

        if let slowResult = await fetchSearchLyrics(for: track, timeout: slowRequestTimeout, relaxed: true) {
            return slowResult
        }

        return FetchCandidate(payload: .unavailable, sourceEndpoint: "lrclib")
    }

    private func fetchFastLyrics(for track: NowPlayingTrack, signature: TrackSignature?) async -> FetchCandidate? {
        await withTaskGroup(of: FetchCandidate?.self) { group in
            if let signature {
                group.addTask { [self] in
                    await fetchSignatureLyrics(
                        signature: signature,
                        endpoint: "https://lrclib.net/api/get-cached",
                        timeout: fastRequestTimeout
                    )
                }

                group.addTask { [self] in
                    await fetchSignatureLyrics(
                        signature: signature,
                        endpoint: "https://lrclib.net/api/get",
                        timeout: fastRequestTimeout
                    )
                }
            }

            if let primarySearch = searchStrategies(for: track, timeout: fastRequestTimeout, relaxed: false).first {
                group.addTask { [self] in
                    await fetchSearchCandidate(strategy: primarySearch, for: track, relaxed: false)
                }
            }

            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }

            return await fetchSearchLyrics(for: track, timeout: fastRequestTimeout, skipPrimary: true, relaxed: false)
        }
    }

    private func makeSignature(for track: NowPlayingTrack) -> TrackSignature? {
        let lookup = lookupIdentity(for: track)
        let trackName = lookup.title
        let artistName = lookup.artist
        let albumName = apiAlbumName(track.identity.album)
        let duration = Int(track.identity.duration.rounded())

        guard !trackName.isEmpty, !artistName.isEmpty, duration > 0 else {
            logger.debug("LRCLIB signature skipped track=\(trackName, privacy: .public) duration=\(duration, privacy: .public)")
            return nil
        }

        return TrackSignature(
            trackName: trackName,
            artistName: artistName,
            albumName: albumName,
            duration: duration
        )
    }

    private func fetchSignatureLyrics(
        signature: TrackSignature,
        endpoint: String,
        timeout: TimeInterval
    ) async -> FetchCandidate? {
        guard var components = URLComponents(string: endpoint) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "track_name", value: signature.trackName),
            URLQueryItem(name: "artist_name", value: signature.artistName),
            URLQueryItem(name: "album_name", value: signature.albumName),
            URLQueryItem(name: "duration", value: String(signature.duration))
        ]

        guard let url = components.url else {
            return nil
        }

        logger.debug("LRCLIB GET \(endpoint, privacy: .public) track=\(signature.trackName, privacy: .public)")

        guard let decoded = await performRequest(url: url, timeout: timeout, decodeAs: LRCLIBResponse.self) else {
            return nil
        }

        return makePayload(from: decoded).map { FetchCandidate(payload: $0, sourceEndpoint: endpoint) }
    }

    private func fetchSearchLyrics(
        for track: NowPlayingTrack,
        timeout: TimeInterval,
        skipPrimary: Bool = false,
        relaxed: Bool
    ) async -> FetchCandidate? {
        var strategies = searchStrategies(for: track, timeout: timeout, relaxed: relaxed)
        if skipPrimary, !strategies.isEmpty {
            strategies.removeFirst()
        }

        guard let bestMatch = await fetchBestSearchMatch(strategies: strategies, for: track, relaxed: relaxed) else {
            return nil
        }

        if let payload = makePayload(from: bestMatch) {
            return FetchCandidate(payload: payload, sourceEndpoint: "https://lrclib.net/api/search")
        }

        if let id = bestMatch.id,
           let exactPayload = await fetchLyricsByID(id) {
            return FetchCandidate(payload: exactPayload, sourceEndpoint: "https://lrclib.net/api/get/{id}")
        }

        return nil
    }

    private func searchStrategies(for track: NowPlayingTrack, timeout: TimeInterval, relaxed: Bool) -> [SearchStrategy] {
        let lookup = lookupIdentity(for: track)
        let trackName = lookup.title
        let artistName = lookup.artist
        let albumName = apiAlbumName(lookup.album)
        let originalTrackName = apiMetadata(track.identity.title)
        let originalArtistName = apiMetadata(track.identity.artist)
        let artistCandidates = uniqueNonEmpty([
            artistName,
            primaryArtistName(originalArtistName),
            originalArtistName
        ])
        let titleCandidates = uniqueNonEmpty([
            trackName,
            titleWithoutVersion(originalTrackName),
            originalTrackName
        ])

        guard !trackName.isEmpty else {
            return []
        }

        var strategies: [[URLQueryItem]] = []

        for title in titleCandidates {
            for artist in artistCandidates {
                var exactItems = [
                    URLQueryItem(name: "track_name", value: title),
                    URLQueryItem(name: "artist_name", value: artist)
                ]
                if hasKnownAlbum(lookup.album) {
                    exactItems.append(URLQueryItem(name: "album_name", value: albumName))
                }
                strategies.append(exactItems)
                strategies.append([
                    URLQueryItem(name: "track_name", value: title),
                    URLQueryItem(name: "artist_name", value: artist)
                ])
            }
        }

        for title in titleCandidates {
            for artist in artistCandidates {
                strategies.append([URLQueryItem(name: "q", value: "\(artist) \(title)")])
                if relaxed {
                    strategies.append([URLQueryItem(name: "q", value: "\(title) \(artist)")])
                }
            }
        }

        for title in titleCandidates {
            strategies.append([URLQueryItem(name: "track_name", value: title)])
            if relaxed {
                strategies.append([URLQueryItem(name: "q", value: title)])
            }
        }

        return uniqueSearchStrategies(strategies)
            .map { SearchStrategy(queryItems: $0, timeout: timeout) }
    }

    private func fetchBestSearchMatch(strategies: [SearchStrategy], for track: NowPlayingTrack, relaxed: Bool) async -> LRCLIBResponse? {
        var best: LRCLIBResponse?
        var bestScore = 0.0

        for strategy in strategies {
            guard !Task.isCancelled else { return nil }

            let results = await performSearch(queryItems: strategy.queryItems, timeout: strategy.timeout)
            if let strategyBest = results
                .filter({ isAcceptableMatch($0, for: track, relaxed: relaxed) })
                .sorted(by: { score($0, for: track) > score($1, for: track) })
                .first {
                let strategyScore = score(strategyBest, for: track)
                if strategyScore > bestScore {
                    best = strategyBest
                    bestScore = strategyScore
                }
                if strategyScore >= 10 {
                    return strategyBest
                }
            }
        }

        return best
    }

    private func fetchSearchCandidate(strategy: SearchStrategy, for track: NowPlayingTrack, relaxed: Bool) async -> FetchCandidate? {
        let results = await performSearch(queryItems: strategy.queryItems, timeout: strategy.timeout)
        guard let bestMatch = results
            .filter({ isAcceptableMatch($0, for: track, relaxed: relaxed) })
            .sorted(by: { score($0, for: track) > score($1, for: track) })
            .first else {
            return nil
        }

        if let payload = makePayload(from: bestMatch) {
            return FetchCandidate(payload: payload, sourceEndpoint: "https://lrclib.net/api/search")
        }

        if let id = bestMatch.id,
           let exactPayload = await fetchLyricsByID(id) {
            return FetchCandidate(payload: exactPayload, sourceEndpoint: "https://lrclib.net/api/get/{id}")
        }

        return nil
    }

    private func performSearch(queryItems: [URLQueryItem], timeout: TimeInterval) async -> [LRCLIBResponse] {
        guard var components = URLComponents(string: "https://lrclib.net/api/search") else {
            return []
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            return []
        }

        logger.debug("LRCLIB search url=\(url.absoluteString, privacy: .public)")

        return await performRequest(url: url, timeout: timeout, decodeAs: [LRCLIBResponse].self) ?? []
    }

    private func fetchLyricsByID(_ id: Int) async -> LyricsPayload? {
        guard let url = URL(string: "https://lrclib.net/api/get/\(id)") else {
            return nil
        }

        guard let decoded = await performRequest(url: url, timeout: fastRequestTimeout, decodeAs: LRCLIBResponse.self) else {
            return nil
        }

        return makePayload(from: decoded)
    }

    private func performRequest<T: Decodable>(
        url: URL,
        timeout: TimeInterval,
        decodeAs: T.Type
    ) async -> T? {
        guard !Task.isCancelled else { return nil }

        do {
            let (data, response) = try await session.data(for: request(for: url, timeout: timeout))
            guard let httpResponse = response as? HTTPURLResponse else {
                return nil
            }

            switch httpResponse.statusCode {
            case 200:
                return try JSONDecoder().decode(T.self, from: data)
            case 404:
                return nil
            default:
                if let errorBody = try? JSONDecoder().decode(LRCLIBErrorResponse.self, from: data) {
                    logger.debug("LRCLIB error status=\(httpResponse.statusCode, privacy: .public) name=\(errorBody.name ?? "unknown", privacy: .public)")
                }
                return nil
            }
        } catch {
            logger.debug("LRCLIB request failed error=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func request(for url: URL, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    static func parseSyncedLyrics(_ text: String) -> [SyncedLyricLine] {
        let timestampPattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: timestampPattern) else {
            return []
        }

        var parsedLines: [SyncedLyricLine] = []
        let rows = text.components(separatedBy: .newlines)

        for row in rows {
            let range = NSRange(row.startIndex..<row.endIndex, in: row)
            let matches = regex.matches(in: row, range: range)
            guard !matches.isEmpty else { continue }

            let lyricStartIndex: String.Index
            if let lastMatch = matches.last,
               let lastRange = Range(lastMatch.range, in: row) {
                lyricStartIndex = lastRange.upperBound
            } else {
                continue
            }

            let lyric = row[lyricStartIndex...]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !lyric.isEmpty else { continue }

            for match in matches {
                guard let minutesRange = Range(match.range(at: 1), in: row),
                      let secondsRange = Range(match.range(at: 2), in: row),
                      let minutes = Double(row[minutesRange]),
                      let seconds = Double(row[secondsRange]) else {
                    continue
                }

                var fractionalSeconds = 0.0
                if match.range(at: 3).location != NSNotFound,
                   let fractionRange = Range(match.range(at: 3), in: row) {
                    let fractionText = String(row[fractionRange])
                    if let fraction = Double(fractionText) {
                        fractionalSeconds = fraction / pow(10, Double(fractionText.count))
                    }
                }

                parsedLines.append(
                    SyncedLyricLine(
                        time: minutes * 60 + seconds + fractionalSeconds,
                        text: lyric
                    )
                )
            }
        }

        return parsedLines.sorted { $0.time < $1.time }
    }

    private func makePayload(from response: LRCLIBResponse) -> LyricsPayload? {
        if response.instrumental == true {
            return .plain("")
        }

        if let synced = response.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
           !synced.isEmpty {
            let lines = Self.parseSyncedLyrics(synced)
            let usableLines = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !usableLines.isEmpty {
                return .synced(usableLines)
            }

            if let plain = response.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
               !plain.isEmpty {
                return .plain(plain)
            }
        }

        if let plain = response.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
           !plain.isEmpty {
            return .plain(plain)
        }

        return nil
    }

    private func selectLyrics(_ payload: LyricsPayload, settings: MiniMusixSettings) -> LyricsPayload {
        switch payload {
        case .loading:
            return .loading
        case .synced(let lines):
            if settings.syncedLyrics {
                return .synced(lines)
            }
            if settings.plainLyrics {
                return .plain(lines.map(\.text).joined(separator: "\n"))
            }
            return .unavailable
        case .plain(let text):
            return settings.plainLyrics ? .plain(text) : .unavailable
        case .unavailable:
            return .unavailable
        }
    }

    private func score(_ response: LRCLIBResponse, for track: NowPlayingTrack) -> Double {
        var score = 0.0
        let lookup = lookupIdentity(for: track)
        if normalized(response.trackName) == normalized(lookup.title) {
            score += 5
        } else if titlesMatch(response.trackName, lookup.title) {
            score += 3
        }
        if normalized(response.artistName) == normalized(lookup.artist) {
            score += 4
        } else if artistsMatch(response.artistName, lookup.artist) {
            score += 2
        }
        if normalized(response.albumName) == normalized(lookup.album) {
            score += 2
        }
        if let duration = response.duration, track.identity.duration > 0 {
            let difference = abs(duration - track.identity.duration)
            if difference <= 2 {
                score += 4
            } else if difference <= 8 {
                score += max(0, 2 - difference / 8)
            }
        }
        if response.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            score += 1
        }
        if response.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            score += 0.5
        }
        return score
    }

    private func isAcceptableMatch(_ response: LRCLIBResponse, for track: NowPlayingTrack, relaxed: Bool) -> Bool {
        let lookup = lookupIdentity(for: track)
        guard titlesMatch(response.trackName, lookup.title) else {
            return false
        }

        let artistMatches = artistsMatch(response.artistName, lookup.artist)
        guard artistMatches || relaxed else {
            return false
        }

        guard let duration = response.duration, track.identity.duration > 0 else {
            return artistMatches
        }

        let difference = abs(duration - track.identity.duration)
        if artistMatches {
            return difference <= (relaxed ? 45 : 18)
        }

        return relaxed && difference <= 8 && score(response, for: track) >= 7
    }

    private func titlesMatch(_ lhs: String?, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right || left.contains(right) || right.contains(left) {
            return true
        }
        return tokenSimilarity(left, right) >= 0.82
    }

    private func artistsMatch(_ lhs: String?, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right || left.contains(right) || right.contains(left) {
            return true
        }

        let leftTokens = Set(left.split(separator: " ").map(String.init).filter { $0.count > 2 })
        let rightTokens = Set(right.split(separator: " ").map(String.init).filter { $0.count > 2 })
        guard !leftTokens.isEmpty, !rightTokens.isEmpty else { return false }
        let intersection = leftTokens.intersection(rightTokens)
        return !intersection.isEmpty && Double(intersection.count) / Double(min(leftTokens.count, rightTokens.count)) >= 0.5
    }

    private func lookupIdentity(for track: NowPlayingTrack) -> MatchIdentity {
        MatchIdentity(
            title: titleWithoutVersion(track.identity.title),
            artist: primaryArtistName(track.identity.artist),
            album: apiMetadata(track.identity.album),
            duration: track.identity.duration
        )
    }

    private func titleWithoutVersion(_ value: String) -> String {
        var cleaned = apiMetadata(value)
        let removableParentheticals = [
            #"\s*[\(\[][^\)\]]*\b(feat|ft|featuring|with|remaster(?:ed)?|deluxe|anniversary|expanded|explicit|clean|radio edit|single version|album version|live|sped up|slowed|nightcore|karaoke|instrumental|acoustic|demo|edit|version)\b[^\)\]]*[\)\]]"#,
            #"\s+-\s+.*\b(remaster(?:ed)?|deluxe|anniversary|expanded|explicit|clean|radio edit|single version|album version|live|sped up|slowed|nightcore|karaoke|instrumental|acoustic|demo|edit|version)\b.*$"#,
            #"\s+\b(feat|ft|featuring)\b\.?\s+.*$"#
        ]

        for pattern in removableParentheticals {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }

        return cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func primaryArtistName(_ value: String) -> String {
        let artist = apiMetadata(value)
        let separators = [
            #"\s+\b(feat|ft|featuring|with)\b\.?\s+"#,
            #"\s*,\s*"#,
            #"\s+&\s+"#,
            #"\s+/\s+"#
        ]

        for separator in separators {
            if let range = artist.range(of: separator, options: [.regularExpression, .caseInsensitive]) {
                return String(artist[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return artist
    }

    private func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in values {
            let trimmed = apiMetadata(value)
            let key = normalized(trimmed)
            guard !trimmed.isEmpty, !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }

        return result
    }

    private func uniqueSearchStrategies(_ strategies: [[URLQueryItem]]) -> [[URLQueryItem]] {
        var seen: Set<String> = []
        var result: [[URLQueryItem]] = []

        for strategy in strategies {
            let key = strategy
                .map { "\($0.name)=\(normalized($0.value ?? ""))" }
                .joined(separator: "&")
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(strategy)
        }

        return result
    }

    private func tokenSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let leftTokens = Set(lhs.split(separator: " ").map(String.init).filter { !$0.isEmpty })
        let rightTokens = Set(rhs.split(separator: " ").map(String.init).filter { !$0.isEmpty })
        guard !leftTokens.isEmpty, !rightTokens.isEmpty else { return 0 }
        let intersection = leftTokens.intersection(rightTokens).count
        let union = leftTokens.union(rightTokens).count
        return Double(intersection) / Double(union)
    }

    private func apiMetadata(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private func apiAlbumName(_ value: String) -> String {
        let album = apiMetadata(value)
        return album.isEmpty ? "Unknown Album" : album
    }

    private func hasKnownAlbum(_ value: String) -> Bool {
        let album = apiMetadata(value).lowercased()
        return !album.isEmpty && album != "unknown album"
    }

    private func normalized(_ value: String?) -> String {
        normalized(value ?? "")
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"\b(feat|ft|featuring|with)\b\.?\s+[^-()\[\]]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\([^)]*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\[[^\]]*\]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b(remaster(?:ed)?|deluxe|anniversary|expanded|explicit|clean|radio edit|single version|album version|live|sped up|slowed|nightcore|karaoke|instrumental|acoustic|demo|edit|version)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
