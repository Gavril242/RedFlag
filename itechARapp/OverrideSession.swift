import Foundation
import Combine

// MARK: - Models

struct OverridePlayer: Codable {
    let id: String
    let username: String
    let teamId: String?
}

struct OverrideTeam: Codable, Identifiable {
    let id: String
    let name: String
    let anthemTitle: String?
    let anthemUrl: String?
    let ownerUserId: String?
    let memberCount: Int?
    let joinable: Bool?
}

struct OverridePoster: Codable, Identifiable {
    let id: String
    let createdAt: Double?
    let strokeCount: Int?
    let stickerCount: Int?
}

struct OverrideStickerAsset: Codable, Identifiable, Hashable {
    let name: String
    let url: String

    var id: String { url }
}

struct PosterAudioAttachment: Codable, Hashable {
    let title: String
    let url: String
}

struct TerritoryState {
    let owner: String?
    let teams: [String: Double]
}

private enum RedFlagServerConfig {
    static let storageKey = "redflag.server_url"
    static let legacyDefaultBaseURL = "http://192.168.168.38:3000"

    static var defaultBaseURL: String {
#if targetEnvironment(simulator)
        return "http://127.0.0.1:3000"
#else
        return "http://localhost:3000"
#endif
    }

    static func normalized(_ rawValue: String?) -> String {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return defaultBaseURL }

        let withScheme: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            withScheme = trimmed
        } else {
            withScheme = "http://\(trimmed)"
        }

        return withScheme.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
    }

    static func candidateBaseURLs(for rawValue: String?) -> [String] {
        let preferred = normalized(rawValue)
        var candidates = [preferred]

        if preferred == legacyDefaultBaseURL || preferred == defaultBaseURL {
            candidates.append(defaultBaseURL)
#if targetEnvironment(simulator)
            candidates.append("http://localhost:3000")
#endif
        }

        var uniqueCandidates: [String] = []
        for candidate in candidates.map(normalized) {
            if !uniqueCandidates.contains(candidate) {
                uniqueCandidates.append(candidate)
            }
        }
        return uniqueCandidates
    }
}

private enum RedFlagClientConfig {
    static func persistIdentity(player: OverridePlayer?, team: OverrideTeam?) {
        let defaults = UserDefaults.standard

        let trimmedUsername = player?.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedUsername, !trimmedUsername.isEmpty {
            defaults.set(trimmedUsername, forKey: OverrideUnityBridgeConfig.usernameDefaultsKey)
        } else {
            defaults.removeObject(forKey: OverrideUnityBridgeConfig.usernameDefaultsKey)
        }

        let resolvedTeamID = (team?.id ?? player?.teamId)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolvedTeamID, !resolvedTeamID.isEmpty {
            defaults.set(resolvedTeamID, forKey: OverrideUnityBridgeConfig.teamIDDefaultsKey)
        } else {
            defaults.removeObject(forKey: OverrideUnityBridgeConfig.teamIDDefaultsKey)
        }
    }

    static func notifyUnityConfigChanged() {
        NotificationCenter.default.post(name: .overrideUnityConfigDidChange, object: nil)
    }
}

// MARK: - Session

@MainActor
final class OverrideSession: ObservableObject {
    static let shared = OverrideSession()

    static let defaultBaseURL = RedFlagServerConfig.defaultBaseURL

    static var baseURL: String {
        RedFlagServerConfig.normalized(UserDefaults.standard.string(forKey: RedFlagServerConfig.storageKey))
    }

    static func resolvedURLString(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let lowered = trimmed.lowercased()
        guard !lowered.hasPrefix("http://"), !lowered.hasPrefix("https://") else { return trimmed }

        if trimmed.range(of: #"^[A-Za-z][A-Za-z0-9+\.-]*:"#,
                         options: .regularExpression) != nil {
            return trimmed
        }

        let knownExternalHosts = [
            "open.spotify.com/",
            "spotify.link/",
            "music.youtube.com/",
            "youtube.com/",
            "www.youtube.com/",
            "m.youtube.com/",
            "youtu.be/"
        ]

        if knownExternalHosts.contains(where: { lowered.hasPrefix($0) }) {
            return "https://\(trimmed)"
        }

        if trimmed.hasPrefix("/") {
            return "\(baseURL)\(trimmed)"
        }
        return "\(baseURL)/\(trimmed)"
    }

    static func normalizedPosterID(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("fig") {
            let suffix = lowered.dropFirst(3)
            if !suffix.isEmpty {
                return "afis\(suffix)"
            }
        }

        return trimmed
    }

    static func isPlaceholderPosterID(_ rawValue: String) -> Bool {
        let lowered = normalizedPosterID(rawValue).lowercased()
        return lowered.isEmpty || lowered == "sector_7_wall"
    }

    @Published var player: OverridePlayer?
    @Published var team: OverrideTeam?
    @Published var availableTeams: [OverrideTeam] = []
    @Published var posters: [OverridePoster] = []
    @Published var isLoggedIn = false
    @Published var hasTeam = false
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var serverURL: String

    // Shared URLSession that persists cookies (override_session)
    let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        return URLSession(configuration: config)
    }()

    private init() {
        serverURL = Self.baseURL
    }

    private func persistUnityRuntimeIdentity() {
        RedFlagClientConfig.persistIdentity(player: player, team: team)
    }

    private func syncUnityRuntimeConfig() {
        persistUnityRuntimeIdentity()
        RedFlagClientConfig.notifyUnityConfigChanged()
    }

    func updateServerURL(_ rawValue: String) {
        let normalizedURL = RedFlagServerConfig.normalized(rawValue)
        UserDefaults.standard.set(normalizedURL, forKey: RedFlagServerConfig.storageKey)
        serverURL = normalizedURL
        errorMessage = nil
        OverrideSocketClient.shared.handleServerEndpointChanged()
        persistUnityRuntimeIdentity()
        UnityManager.shared.setServerURL(normalizedURL)
    }

    func resetServerURL() {
        updateServerURL(Self.defaultBaseURL)
    }

    // MARK: - Register

    func register(username: String, password: String) async {
        guard let url = apiURL("/api/auth/register") else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "username": username,
            "password": password
        ])

        do {
            let (data, _) = try await urlSession.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            if let ok = json["ok"] as? Bool, ok,
               let userDict = Self.dictionaryValue(json["user"]) ?? Self.dictionaryValue(json["player"]) {
                let id = Self.stringValue(userDict["id"]) ?? ""
                let uname = Self.stringValue(userDict["username"]) ?? username
                let teamId = Self.stringValue(userDict["teamId"])
                player = OverridePlayer(id: id, username: uname, teamId: teamId)
                isLoggedIn = true

                if let teamDict = Self.dictionaryValue(json["team"]) {
                    team = parseTeam(teamDict)
                    hasTeam = true
                }
                syncUnityRuntimeConfig()
            } else {
                errorMessage = Self.stringValue(json["error"]) ?? "Registration failed on \(serverURL)"
            }
        } catch {
            errorMessage = networkFailureMessage(action: "Registration", error: error)
        }
    }

    // MARK: - Login

    func login(username: String, password: String) async {
        guard let url = apiURL("/api/auth/login") else { return }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "username": username,
            "password": password
        ])

        do {
            let (data, _) = try await urlSession.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            if let ok = json["ok"] as? Bool, ok,
               let userDict = Self.dictionaryValue(json["user"]) ?? Self.dictionaryValue(json["player"]) {
                let id = Self.stringValue(userDict["id"]) ?? ""
                let uname = Self.stringValue(userDict["username"]) ?? username
                let teamId = Self.stringValue(userDict["teamId"])
                player = OverridePlayer(id: id, username: uname, teamId: teamId)
                isLoggedIn = true

                if let teamDict = Self.dictionaryValue(json["team"]) {
                    team = parseTeam(teamDict)
                    hasTeam = true
                }
                syncUnityRuntimeConfig()
            } else {
                errorMessage = Self.stringValue(json["error"]) ?? "Login failed on \(serverURL)"
            }
        } catch {
            errorMessage = networkFailureMessage(action: "Login", error: error)
        }
    }

    // MARK: - Teams

    func fetchTeams() async {
        guard let url = apiURL("/api/teams") else { return }

        do {
            let (data, _) = try await urlSession.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data)
            let teamArray = Self.objectArray(from: json, keys: ["teams", "items", "data"])
            if !teamArray.isEmpty {
                availableTeams = teamArray.compactMap(parseTeam)
                errorMessage = nil
            }
        } catch {
            errorMessage = networkFailureMessage(action: "Fetch teams", error: error)
        }
    }

    func createTeam(name: String) async {
        guard let url = apiURL("/api/teams") else { return }
        errorMessage = nil

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name])

        do {
            let (data, _) = try await urlSession.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            if let ok = json["ok"] as? Bool, ok {
                if let teamDict = Self.dictionaryValue(json["team"]) {
                    team = parseTeam(teamDict)
                    hasTeam = true
                }
                if let userDict = Self.dictionaryValue(json["user"]) ?? Self.dictionaryValue(json["player"]) {
                    player = OverridePlayer(
                        id: Self.stringValue(userDict["id"]) ?? player?.id ?? "",
                        username: Self.stringValue(userDict["username"]) ?? player?.username ?? "",
                        teamId: Self.stringValue(userDict["teamId"])
                    )
                }
                syncUnityRuntimeConfig()
            } else {
                errorMessage = Self.stringValue(json["error"]) ?? "Create team failed on \(serverURL)"
            }
        } catch {
            errorMessage = networkFailureMessage(action: "Create team", error: error)
        }
    }

    func joinTeam(teamId: String) async {
        guard let url = apiURL("/api/teams/\(teamId)/join") else { return }
        errorMessage = nil

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)

        do {
            let (data, _) = try await urlSession.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

            if let ok = json["ok"] as? Bool, ok {
                if let teamDict = Self.dictionaryValue(json["team"]) {
                    team = parseTeam(teamDict)
                    hasTeam = true
                }
                if let userDict = Self.dictionaryValue(json["user"]) ?? Self.dictionaryValue(json["player"]) {
                    player = OverridePlayer(
                        id: Self.stringValue(userDict["id"]) ?? player?.id ?? "",
                        username: Self.stringValue(userDict["username"]) ?? player?.username ?? "",
                        teamId: Self.stringValue(userDict["teamId"])
                    )
                }
                syncUnityRuntimeConfig()
            } else {
                errorMessage = Self.stringValue(json["error"]) ?? "Join failed on \(serverURL)"
            }
        } catch {
            errorMessage = networkFailureMessage(action: "Join team", error: error)
        }
    }

    // MARK: - Posters

    func fetchPosters() async {
        do {
            let (data, response, resolvedBaseURL) = try await performRequest(
                path: "/api/posters",
                allowFallback: true
            )
            promoteServerURLIfNeeded(resolvedBaseURL)

            if let http = response as? HTTPURLResponse,
               !(200 ..< 300).contains(http.statusCode) {
                posters = []
                errorMessage = httpFailureMessage(
                    action: "Fetch posters",
                    statusCode: http.statusCode,
                    data: data,
                    baseURL: resolvedBaseURL
                )
                return
            }

            let decoder = JSONDecoder()
            if let list = try? decoder.decode([OverridePoster].self, from: data) {
                posters = list
                errorMessage = nil
                return
            }

            let json = try JSONSerialization.jsonObject(with: data)
            let parsed = OverrideSession.parsePosterList(from: json)
            if !parsed.isEmpty {
                posters = parsed
                errorMessage = nil
            } else {
                posters = []
                errorMessage = "Fetch posters returned an unrecognized payload from \(resolvedBaseURL)"
            }
        } catch {
            errorMessage = networkFailureMessage(action: "Fetch posters", error: error)
        }
    }

    func fetchStickerLibrary() async -> [OverrideStickerAsset] {
        guard let url = apiURL("/api/stickers/library") else { return Self.fallbackStickerLibrary }

        do {
            let (data, _) = try await urlSession.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data)
            let stickerPayloads = Self.objectArray(from: json, keys: ["stickers", "items", "library", "assets", "data"])
            let parsed = stickerPayloads.compactMap(Self.parseStickerAsset)
            if !parsed.isEmpty {
                errorMessage = nil
                return Self.mergedStickerLibrary(parsed)
            }
        } catch {
            errorMessage = "Sticker library unavailable on \(serverURL): \(error.localizedDescription)"
        }

        return Self.fallbackStickerLibrary
    }

    func attachPosterAudio(posterId: String, title: String, urlString: String) async -> PosterAudioAttachment? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Audio title and URL are required"
            return nil
        }

        let payload = await requestPosterAudio(
            posterId: posterId,
            method: "POST",
            pathSuffix: "/audio",
            body: [
                "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
                "url": Self.resolvedURLString(urlString.trimmingCharacters(in: .whitespacesAndNewlines))
            ]
        )

        guard let audioPayload = Self.dictionaryValue(payload?["audio"]) ?? Self.dictionaryValue(payload?["posterAudio"]) else {
            return nil
        }
        return Self.parsePosterAudio(audioPayload)
    }

    func triggerPosterAudio(posterId: String) async -> PosterAudioAttachment? {
        let payload = await requestPosterAudio(
            posterId: posterId,
            method: "POST",
            pathSuffix: "/audio/trigger",
            body: [:]
        )

        if let audioPayload = Self.dictionaryValue(payload?["audio"]) ?? Self.dictionaryValue(payload?["posterAudio"]) {
            return Self.parsePosterAudio(audioPayload)
        }

        return nil
    }

    func clearPosterAudio(posterId: String) async -> Bool {
        let payload = await requestPosterAudio(
            posterId: posterId,
            method: "DELETE",
            pathSuffix: "/audio"
        )

        return (payload?["ok"] as? Bool) == true
    }

    private func requestPosterAudio(
        posterId: String,
        method: String,
        pathSuffix: String,
        body: [String: Any]? = nil
    ) async -> [String: Any]? {
        let resolvedPosterId = Self.normalizedPosterID(posterId)
        guard !resolvedPosterId.isEmpty,
              let encodedPosterId = resolvedPosterId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = apiURL("/api/posters/\(encodedPosterId)\(pathSuffix)") else {
            return nil
        }

        errorMessage = nil

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        do {
            let (data, _) = try await urlSession.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            if let ok = json["ok"] as? Bool, !ok {
                errorMessage = Self.stringValue(json["error"]) ?? "Audio request failed on \(serverURL)"
            }
            return json
        } catch {
            errorMessage = networkFailureMessage(action: "Audio request", error: error)
            return nil
        }
    }

    // MARK: - Helpers

    private func apiURL(_ path: String) -> URL? {
        URL(string: "\(serverURL)\(path)")
    }

    private func performRequest(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        allowFallback: Bool = false
    ) async throws -> (Data, URLResponse, String) {
        let candidateBaseURLs = allowFallback
            ? RedFlagServerConfig.candidateBaseURLs(for: serverURL)
            : [serverURL]

        var lastError: Error?

        for candidateBaseURL in candidateBaseURLs {
            guard let url = URL(string: "\(candidateBaseURL)\(path)") else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = method
            if let body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            }

            do {
                let (data, response) = try await urlSession.data(for: request)
                return (data, response, candidateBaseURL)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? URLError(.cannotConnectToHost)
    }

    private func promoteServerURLIfNeeded(_ resolvedBaseURL: String) {
        let normalizedBaseURL = RedFlagServerConfig.normalized(resolvedBaseURL)
        guard normalizedBaseURL != serverURL else { return }
        updateServerURL(normalizedBaseURL)
    }

    private func httpFailureMessage(action: String, statusCode: Int, data: Data, baseURL: String) -> String {
        if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let backendMessage = Self.firstString(in: json, keys: ["error", "message", "detail"]),
           !backendMessage.isEmpty {
            return "\(action) failed on \(baseURL): \(backendMessage)"
        }

        return "\(action) failed on \(baseURL): HTTP \(statusCode)"
    }

    private func networkFailureMessage(action: String, error: Error) -> String {
        let routeHint = serverURL == Self.defaultBaseURL || serverURL == RedFlagServerConfig.legacyDefaultBaseURL
            ? " Check the app's Backend Route if your LAN IP changed."
            : ""
        return "\(action) failed on \(serverURL): \(error.localizedDescription)\(routeHint)"
    }

    private func parseTeam(_ dict: [String: Any]) -> OverrideTeam? {
        guard let id = Self.stringValue(dict["id"]),
              let name = Self.stringValue(dict["name"]) else {
            return nil
        }

        let anthemURL = Self.stringValue(dict["anthemUrl"]).map(Self.resolvedURLString)

        return OverrideTeam(
            id: id,
            name: name,
            anthemTitle: Self.stringValue(dict["anthemTitle"]),
            anthemUrl: anthemURL,
            ownerUserId: Self.stringValue(dict["ownerUserId"]),
            memberCount: Self.intValue(dict["memberCount"]),
            joinable: Self.boolValue(dict["joinable"])
        )
    }
}

extension OverrideSession {
    static func parsePosterList(from json: Any) -> [OverridePoster] {
        let objectPayloads = objectArray(from: json, keys: ["posters", "items", "data", "rooms"])
        if !objectPayloads.isEmpty {
            return objectPayloads.compactMap(parsePoster)
        }

        let posterIDs = stringArray(from: json, keys: ["posters", "items", "data", "rooms", "posterIds", "roomIds"])
            .map(normalizedPosterID)
            .filter { !$0.isEmpty }
        if !posterIDs.isEmpty {
            return posterIDs.map { OverridePoster(id: $0, createdAt: nil, strokeCount: nil, stickerCount: nil) }
        }

        if let posterMap = dictionaryPayload(from: json, keys: ["posters", "items", "data", "rooms"]) {
            let parsed = posterMap.compactMap { key, value -> OverridePoster? in
                guard var payload = value as? [String: Any] else { return nil }
                if payload["id"] == nil, payload["posterId"] == nil {
                    payload["id"] = key
                }
                return parsePoster(payload)
            }
            if !parsed.isEmpty {
                return parsed.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
            }
        }

        return []
    }

    private static func dictionaryValue(_ rawValue: Any?) -> [String: Any]? {
        rawValue as? [String: Any]
    }

    private static func objectArray(from json: Any, keys: [String]) -> [[String: Any]] {
        arrayValue(from: json, keys: keys).compactMap { $0 as? [String: Any] }
    }

    private static func stringArray(from json: Any, keys: [String]) -> [String] {
        arrayValue(from: json, keys: keys).compactMap(stringValue)
    }

    private static func arrayValue(from json: Any, keys: [String]) -> [Any] {
        if let array = json as? [Any] {
            return array
        }

        guard let dictionary = json as? [String: Any] else { return [] }

        for key in keys {
            if let array = dictionary[key] as? [Any] {
                return array
            }
        }

        if let nested = dictionary["data"] as? [String: Any] {
            let nestedArray = arrayValue(from: nested, keys: keys)
            if !nestedArray.isEmpty {
                return nestedArray
            }
        }

        return []
    }

    private static func dictionaryPayload(from json: Any, keys: [String]) -> [String: Any]? {
        if let dictionary = json as? [String: Any] {
            for key in keys {
                if let nested = dictionary[key] as? [String: Any] {
                    return nested
                }
            }

            if let nested = dictionary["data"] as? [String: Any] {
                return dictionaryPayload(from: nested, keys: keys)
            }
        }

        return nil
    }

    private static func stringValue(_ rawValue: Any?) -> String? {
        switch rawValue {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private static func doubleValue(_ rawValue: Any?) -> Double? {
        switch rawValue {
        case let value as Double:
            return value
        case let value as Float:
            return Double(value)
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private static func intValue(_ rawValue: Any?) -> Int? {
        switch rawValue {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private static func boolValue(_ rawValue: Any?) -> Bool? {
        switch rawValue {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            return ["true", "1", "yes"].contains(value.lowercased())
        default:
            return nil
        }
    }

    private static func firstString(in payload: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = stringValue(payload[key]), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func parsePoster(_ item: [String: Any]) -> OverridePoster? {
        guard let id = firstString(in: item, keys: ["id", "posterId", "roomId", "slug", "name"]) else { return nil }

        return OverridePoster(
            id: normalizedPosterID(id),
            createdAt: doubleValue(item["createdAt"]) ?? doubleValue(item["created_at"]),
            strokeCount: intValue(item["strokeCount"]) ?? intValue(item["strokesCount"]) ?? intValue(item["strokes"]),
            stickerCount: intValue(item["stickerCount"]) ?? intValue(item["stickersCount"]) ?? intValue(item["stickers"])
        )
    }

    private static func parseStickerAsset(_ item: [String: Any]) -> OverrideStickerAsset? {
        guard let rawURL = firstString(in: item, keys: ["url", "gifUrl", "imageUrl", "assetUrl", "src"]) else {
            return nil
        }

        let name = firstString(in: item, keys: ["name", "title", "label"]) ?? "Sticker"
        return OverrideStickerAsset(name: name, url: resolvedURLString(rawURL))
    }

    private static func parsePosterAudio(_ dict: [String: Any]) -> PosterAudioAttachment? {
        guard let rawURL = firstString(in: dict, keys: ["url", "audioUrl", "src"]) else { return nil }

        return PosterAudioAttachment(
            title: firstString(in: dict, keys: ["title", "name", "label"]) ?? "Poster Audio",
            url: resolvedURLString(rawURL)
        )
    }

    private static func mergedStickerLibrary(_ backendAssets: [OverrideStickerAsset]) -> [OverrideStickerAsset] {
        var merged: [OverrideStickerAsset] = []
        var seenURLs = Set<String>()

        for asset in backendAssets + fallbackStickerLibrary {
            guard seenURLs.insert(asset.url).inserted else { continue }
            merged.append(asset)
        }

        return merged
    }

    static let fallbackStickerLibrary: [OverrideStickerAsset] = [
        OverrideStickerAsset(name: "Glitch Cat", url: "https://media.giphy.com/media/ICOgUNjpvO0PC/giphy.gif"),
        OverrideStickerAsset(name: "Hack Pulse", url: "https://media.giphy.com/media/JIX9t2j0ZTN9S/giphy.gif"),
        OverrideStickerAsset(name: "Signal Burst", url: "https://media.giphy.com/media/l0HlBO7eyXzSZkJri/giphy.gif"),
        OverrideStickerAsset(name: "Neon Skull", url: "https://media.giphy.com/media/3oriO0OEd9QIDdllqo/giphy.gif"),
        OverrideStickerAsset(name: "Arcade Heart", url: "https://media.giphy.com/media/xT9IgzoKnwFNmISR8I/giphy.gif")
    ]
}
