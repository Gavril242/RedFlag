import Foundation
import Combine
import AVFoundation
import UIKit
import WebKit

// MARK: - Canvas State Models

struct CanvasPoint: Hashable {
    let x: Double
    let y: Double
}

struct CanvasLayout: Hashable {
    let width: Double
    let height: Double
    let aspectRatio: Double
    let origin: String

    static let a4Portrait = CanvasLayout(width: 1000, height: 1414, aspectRatio: 1000.0 / 1414.0, origin: "top-left")
}

struct CanvasStroke: Identifiable, Hashable {
    let id: String
    let teamId: String
    let userId: String?
    let color: String
    let width: Double
    let points: [CanvasPoint]
}

struct CanvasSticker: Identifiable, Hashable {
    let id: String
    let teamId: String
    let url: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let rotation: Double
}

enum SocketConnectionState: String {
    case disconnected = "OFFLINE"
    case connecting = "CONNECTING"
    case syncing = "SYNCING"
    case live = "LIVE"
    case failed = "FAILED"
}

private enum SocketTransportMode {
    case webSocket
    case polling
}

private enum SocketClientError: LocalizedError {
    case timeout
    case malformedOpenPacket
    case unsupportedMessage

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "The socket handshake timed out."
        case .malformedOpenPacket:
            return "The socket open packet could not be parsed."
        case .unsupportedMessage:
            return "The socket returned an unsupported message type."
        }
    }
}

private enum PosterAudioSource: Equatable {
    case direct(URL)
    case youtube(videoID: String)
    case spotify(uri: String)
}

private enum PosterAudioSourceResolver {
    static func resolve(_ rawValue: String) -> PosterAudioSource? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("spotify:") {
            return .spotify(uri: trimmed)
        }

        guard let url = URL(string: trimmed) else { return nil }
        let host = (url.host ?? "").lowercased()

        if let videoID = youtubeVideoID(from: url) {
            return .youtube(videoID: videoID)
        }

        if let uri = spotifyURI(from: trimmed, url: url) {
            return .spotify(uri: uri)
        }

        if host.contains("youtube") || host == "youtu.be" || host.contains("spotify") {
            return nil
        }

        switch url.scheme?.lowercased() {
        case "http", "https":
            return .direct(url)
        default:
            return nil
        }
    }

    private static func youtubeVideoID(from url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if host == "youtu.be", let first = pathComponents.first, !first.isEmpty {
            return first
        }

        guard host.contains("youtube.com") else { return nil }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value,
           !videoID.isEmpty {
            return videoID
        }

        if let index = pathComponents.firstIndex(of: "embed"),
           pathComponents.indices.contains(index + 1) {
            return pathComponents[index + 1]
        }

        if let index = pathComponents.firstIndex(of: "shorts"),
           pathComponents.indices.contains(index + 1) {
            return pathComponents[index + 1]
        }

        if let index = pathComponents.firstIndex(of: "live"),
           pathComponents.indices.contains(index + 1) {
            return pathComponents[index + 1]
        }

        return nil
    }

    private static func spotifyURI(from rawValue: String, url: URL) -> String? {
        let host = (url.host ?? "").lowercased()
        guard host.contains("spotify.com") else { return nil }

        let supportedKinds = ["track", "album", "playlist", "episode", "show", "artist"]
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        for (index, component) in pathComponents.enumerated() where supportedKinds.contains(component) {
            guard pathComponents.indices.contains(index + 1) else { continue }
            let identifier = pathComponents[index + 1]
            guard !identifier.isEmpty else { continue }
            return "spotify:\(component):\(identifier)"
        }

        if rawValue.contains("/embed/") {
            for kind in supportedKinds {
                let marker = "/embed/\(kind)/"
                if let range = rawValue.range(of: marker) {
                    let identifier = rawValue[range.upperBound...]
                        .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: true)
                        .first
                        .map(String.init) ?? ""
                    if !identifier.isEmpty {
                        return "spotify:\(kind):\(identifier)"
                    }
                }
            }
        }

        return nil
    }
}

@MainActor
private final class PosterAudioEmbeddedPlayer: NSObject {
    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.alpha = 0.02
        return view
    }()

    private var isAttached = false

    func play(_ source: PosterAudioSource) {
        ensureAttached()

        switch source {
        case let .youtube(videoID):
            if let embedURL = youtubeEmbedURL(videoID: videoID) {
                webView.load(URLRequest(url: embedURL))
            }
        case let .spotify(uri):
            webView.loadHTMLString(spotifyMarkup(uri: uri), baseURL: URL(string: "https://open.spotify.com"))
        case .direct:
            break
        }
    }

    func stop() {
        guard isAttached else { return }
        webView.evaluateJavaScript("window.pauseEmbeddedAudio && window.pauseEmbeddedAudio();", completionHandler: nil)
        webView.loadHTMLString("<html><body style='background:transparent;'></body></html>", baseURL: nil)
    }

    private func ensureAttached() {
        guard !isAttached else { return }
        guard let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else {
            return
        }

        webView.translatesAutoresizingMaskIntoConstraints = false
        keyWindow.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.widthAnchor.constraint(equalToConstant: 220),
            webView.heightAnchor.constraint(equalToConstant: 220),
            webView.trailingAnchor.constraint(equalTo: keyWindow.trailingAnchor, constant: -12),
            webView.bottomAnchor.constraint(equalTo: keyWindow.bottomAnchor, constant: -12)
        ])
        isAttached = true
    }

    private func youtubeEmbedURL(videoID: String) -> URL? {
        guard !videoID.isEmpty else { return nil }

        var components = URLComponents(string: "https://www.youtube.com/embed/\(videoID)")
        components?.queryItems = [
            URLQueryItem(name: "autoplay", value: "1"),
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "controls", value: "0"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "modestbranding", value: "1"),
            URLQueryItem(name: "loop", value: "1"),
            URLQueryItem(name: "playlist", value: videoID)
        ]
        return components?.url
    }

    private func spotifyMarkup(uri: String) -> String {
        let escapedURI = escapeJavaScript(uri)

        return """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
        <style>
        html, body, #embed-iframe {
          margin: 0;
          padding: 0;
          width: 100%;
          height: 100%;
          overflow: hidden;
          background: transparent;
        }
        </style>
        </head>
        <body>
        <div id="embed-iframe"></div>
        <script src="https://open.spotify.com/embed/iframe-api/v1" async></script>
        <script>
        let spotifyController = null;
        window.onSpotifyIframeApiReady = (IFrameAPI) => {
          const element = document.getElementById('embed-iframe');
          const options = {
            uri: '\(escapedURI)',
            width: 220,
            height: 220,
            theme: 'dark'
          };
          const callback = (EmbedController) => {
            spotifyController = EmbedController;
            setTimeout(() => {
              try { EmbedController.loadUri('\(escapedURI)'); } catch (error) {}
              try { EmbedController.togglePlay(); } catch (error) {}
            }, 500);
          };
          IFrameAPI.createController(element, options, callback);
        };
        window.pauseEmbeddedAudio = function() {
          if (spotifyController && spotifyController.pause) {
            spotifyController.pause();
          }
        };
        </script>
        </body>
        </html>
        """
    }

    private func escapeJavaScript(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

// MARK: - Socket Client
// Uses Socket.IO polling transport so we can stay dependency-light.

@MainActor
final class OverrideSocketClient: ObservableObject {
    static let shared = OverrideSocketClient()

    @Published var strokes: [CanvasStroke] = []
    @Published var stickers: [CanvasSticker] = []
    @Published var territory: [String: Double] = [:]
    @Published var posterOwner: String?
    @Published var rawArea: [String: Double] = [:]
    @Published var canvasCleared = false
    @Published var currentPosterId: String?
    @Published var currentLayout: CanvasLayout = .a4Portrait
    @Published var isPlayingAnthem = false
    @Published var currentAnthemTitle: String?
    @Published var posterAudio: PosterAudioAttachment?
    @Published var connectionState: SocketConnectionState = .disconnected
    @Published var connectionErrorMessage: String?

    private var audioPlayer: AVPlayer?
    private let embeddedAudioPlayer = PosterAudioEmbeddedPlayer()

    private var sid: String?
    private var pollTask: Task<Void, Never>?
    private var webSocketTask: URLSessionWebSocketTask?
    private var webSocketReceiveTask: Task<Void, Never>?
    private var isConnected = false
    private var namespaceConnected = false
    private var didSendNamespaceConnect = false
    private var transportMode: SocketTransportMode?
    private var currentTeamId: String?
    private var currentUserId: String?
    private var currentUsername: String?
    private var isRecoveringConnection = false
    private var activeAudioPosterId: String?
    private var activeAudioURL: String?

    private var base: String { OverrideSession.baseURL }
    private var transportSession: URLSession { OverrideSession.shared.urlSession }

    private init() {}

    func handleServerEndpointChanged() {
        disconnect()
        stopAudio()
        resetTransientCanvasState()
        connectionErrorMessage = nil
    }

    // MARK: - Connection

    @discardableResult
    func connect() async -> Bool {
        guard !isConnected else { return true }

        connectionState = .connecting
        connectionErrorMessage = nil

        if await connectWebSocket() {
            return true
        }

        return await connectPolling()
    }

    private func connectPolling() async -> Bool {
        guard let url = socketURL(transport: "polling") else {
            setFailure("Socket URL is invalid for \(base)")
            return false
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15

            let (data, response) = try await transportSession.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200 ..< 300).contains(http.statusCode) {
                setFailure("Socket handshake returned \(http.statusCode) from \(base)")
                return false
            }

            guard let body = String(data: data, encoding: .utf8),
                  let jsonStart = body.firstIndex(of: "{"),
                  let json = try? JSONSerialization.jsonObject(with: Data(body[jsonStart...].utf8)) as? [String: Any],
                  let sessionId = stringValue(json["sid"]) else {
                setFailure("Socket handshake payload from \(base) was not recognized")
                return false
            }

            sid = sessionId
            isConnected = true
            namespaceConnected = false
            didSendNamespaceConnect = false
            transportMode = .polling
            connectionState = .syncing
            startPolling()
            _ = await sendNamespaceConnectPacket()
            return true
        } catch {
            setFailure("Socket polling connect failed for \(base): \(error.localizedDescription)")
            return false
        }
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        webSocketReceiveTask?.cancel()
        webSocketReceiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        namespaceConnected = false
        didSendNamespaceConnect = false
        sid = nil
        transportMode = nil
        connectionState = .disconnected
    }

    // MARK: - Poster Room

    func joinPoster(posterId: String, teamId: String, userId: String?, username: String) async {
        let resolvedPosterId = OverrideSession.normalizedPosterID(posterId)
        guard !resolvedPosterId.isEmpty else { return }

        currentTeamId = teamId
        currentUserId = userId
        currentUsername = username

        _ = await connect()

        currentPosterId = resolvedPosterId
        resetTransientCanvasState(keepPosterId: true, preservePlaybackState: true)

        let payload: [String: Any] = [
            "posterId": resolvedPosterId,
            "teamId": teamId,
            "userId": userId ?? username,
            "username": username,
            "coordinateMeta": coordinateMeta,
            "layout": layoutPayload
        ]

        _ = await emit(event: "join_poster", data: payload)
        await reloadPosterState(posterId: resolvedPosterId)
        activateCurrentPosterAudioIfNeeded()
    }

    func reloadPosterState(posterId: String? = nil) async {
        let activePosterId = OverrideSession.normalizedPosterID(posterId ?? currentPosterId ?? "")
        guard !activePosterId.isEmpty else { return }

        let encodedPosterId = activePosterId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? activePosterId
        async let canvasResponse = requestJSON(path: "/api/posters/\(encodedPosterId)/canvas")
        async let territoryResponse = requestJSON(path: "/api/posters/\(encodedPosterId)/territory")

        let (canvasPayload, territoryPayload) = await (canvasResponse, territoryResponse)
        if let canvasPayload {
            applyCanvasState(canvasPayload)
        }
        if let territoryPayload {
            applyTerritoryState(territoryPayload)
        }
    }

    // MARK: - Draw / Sticker Emit

    @discardableResult
    func emitStroke(
        posterId: String,
        teamId: String,
        userId: String,
        username: String,
        color: String,
        width: Double,
        points: [(Double, Double)]
    ) async -> Bool {
        let resolvedPosterId = OverrideSession.normalizedPosterID(posterId)
        guard !resolvedPosterId.isEmpty, !points.isEmpty else { return false }

        let payload: [String: Any] = [
            "posterId": resolvedPosterId,
            "teamId": teamId,
            "userId": userId,
            "username": username,
            "color": color,
            "strokeColor": color,
            "lineColor": color,
            "hexColor": color,
            "brushColor": color,
            "width": width,
            "layout": layoutPayload,
            "coordinateMeta": coordinateMeta,
            "points": points.map { ["x": $0.0, "y": $0.1] }
        ]

        return await emit(event: "draw_stroke", data: payload)
    }

    @discardableResult
    func emitSticker(
        posterId: String,
        teamId: String,
        userId: String,
        username: String,
        url: String,
        x: Double,
        y: Double,
        w: Double,
        h: Double,
        rotation: Double = 0
    ) async -> Bool {
        let resolvedPosterId = OverrideSession.normalizedPosterID(posterId)
        guard !resolvedPosterId.isEmpty else { return false }

        let resolvedURL = OverrideSession.resolvedURLString(url)
        let payload: [String: Any] = [
            "posterId": resolvedPosterId,
            "teamId": teamId,
            "userId": userId,
            "username": username,
            "url": resolvedURL,
            "gifUrl": resolvedURL,
            "imageUrl": resolvedURL,
            "x": x,
            "y": y,
            "width": w,
            "height": h,
            "w": w,
            "h": h,
            "rotation": rotation,
            "layout": layoutPayload,
            "coordinateMeta": coordinateMeta
        ]

        return await emit(event: "place_sticker", data: payload)
    }

    func previewAudio(_ audio: PosterAudioAttachment, posterId: String? = nil) {
        posterAudio = audio
        playAudio(audio: audio, posterId: posterId ?? currentPosterId)
    }

    func clearAudioState() {
        stopAudio()
    }

    // MARK: - Emit (Socket.IO polling)

    @discardableResult
    private func emit(event: String, data: [String: Any]) async -> Bool {
        if !isConnected || sid == nil {
            guard await connect() else { return false }
        }

        if !namespaceConnected {
            _ = await sendNamespaceConnectPacket()
        }

        guard let payloadData = try? JSONSerialization.data(withJSONObject: data),
              let payloadString = String(data: payloadData, encoding: .utf8) else {
            setFailure("Socket payload for \(event) could not be encoded")
            return false
        }

        let body = "42[\"\(event)\",\(payloadString)]"
        return await sendTextPacket(body, context: event)
    }

    @discardableResult
    private func sendNamespaceConnectPacket() async -> Bool {
        guard !didSendNamespaceConnect else { return true }
        let success = await sendRawPacket("40")
        if success {
            didSendNamespaceConnect = true
        }
        return success
    }

    @discardableResult
    private func sendTextPacket(_ packet: String, context: String) async -> Bool {
        switch transportMode {
        case .webSocket:
            return await sendWebSocketPacket(packet, context: context)
        case .polling:
            return await sendPollingPacket(packet, context: context)
        case .none:
            setFailure("Socket transport is not ready for \(context)")
            return false
        }
    }

    @discardableResult
    private func sendPollingPacket(_ packet: String, context: String) async -> Bool {
        guard let sid,
              let url = socketURL(transport: "polling", sid: sid),
              let body = packet.data(using: .utf8) else {
            setFailure("Socket polling request could not be created for \(context)")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 15

        do {
            let (_, response) = try await transportSession.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200 ..< 300).contains(http.statusCode) {
                setFailure("\(context) returned \(http.statusCode) from \(base)")
                if http.statusCode == 400 {
                    await recoverConnectionIfPossible(reason: "Socket polling session was rejected by the server")
                }
                return false
            }

            if connectionState != .live {
                connectionState = .syncing
            }
            return true
        } catch {
            setFailure("\(context) failed on \(base): \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    private func sendRawPacket(_ packet: String) async -> Bool {
        await sendTextPacket(packet, context: "socket namespace sync")
    }

    @discardableResult
    private func sendWebSocketPacket(_ packet: String, context: String) async -> Bool {
        guard let webSocketTask else {
            setFailure("Socket websocket is unavailable for \(context)")
            return false
        }

        do {
            try await webSocketTask.send(.string(packet))
            return true
        } catch {
            setFailure("\(context) failed on \(base): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Polling Loop

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    private func poll() async {
        guard let sid,
              let url = socketURL(transport: "polling", sid: sid) else {
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 55

            let (data, response) = try await transportSession.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200 ..< 300).contains(http.statusCode) {
                setFailure("Socket polling returned \(http.statusCode) from \(base)")
                if http.statusCode == 400 {
                    await recoverConnectionIfPossible(reason: "Socket polling session was rejected by the server")
                }
                return
            }

            guard let body = String(data: data, encoding: .utf8) else { return }

            let packets = body.components(separatedBy: "\u{1e}")
            for packet in packets {
                await handleInboundPacket(packet)
            }
        } catch {
            guard !Task.isCancelled else { return }
            setFailure("Socket polling failed for \(base): \(error.localizedDescription)")
        }
    }

    private func handleInboundPacket(_ packet: String) async {
        guard !packet.isEmpty else { return }

        switch packet {
        case "2":
            _ = await sendRawPacket("3")
        case "3":
            break
        default:
            if packet.hasPrefix("0") {
                if let sessionId = parseOpenPacket(packet) {
                    sid = sessionId
                    connectionErrorMessage = nil
                }
                return
            }

            if packet.hasPrefix("40") {
                namespaceConnected = true
                connectionState = .live
                connectionErrorMessage = nil
                return
            }

            if packet.hasPrefix("41") {
                namespaceConnected = false
                connectionState = .failed
                return
            }

            if packet.hasPrefix("42") {
                parsePacket(packet)
            }
        }
    }

    private func parsePacket(_ packet: String) {
        guard packet.hasPrefix("42") else { return }
        let jsonString = String(packet.dropFirst(2))
        guard let data = jsonString.data(using: .utf8),
              let payloadArray = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let event = payloadArray.first as? String,
              let payload = payloadArray.dropFirst().first as? [String: Any] else {
            return
        }

        connectionErrorMessage = nil

        switch event {
        case "dashboard_update":
            applyDashboardState(payload)
        case "canvas_state":
            applyCanvasState(payload)
        case "stroke_added":
            handleStrokeAdded(payload)
        case "sticker_added":
            handleStickerAdded(payload)
        case "territory_update", "territory_state":
            applyTerritoryState(payload)
        case "canvas_cleared":
            handleCanvasCleared(payload)
        case "sticker_removed":
            handleStickerRemoved(payload)
        case "poster_audio_trigger", "poster_audio_updated":
            handleAudioTrigger(payload)
        case "poster_audio_cleared":
            handleAudioCleared(payload)
        default:
            break
        }
    }

    // MARK: - Audio

    private func handleAudioTrigger(_ payload: [String: Any]) {
        if let shouldPlay = boolValue(payload["shouldPlay"]), !shouldPlay {
            return
        }

        let audioPayload = dictionaryValue(payload["audio"]) ?? dictionaryValue(payload["posterAudio"]) ?? payload
        guard let audio = parseAudio(audioPayload) else {
            return
        }

        posterAudio = audio
        playAudio(audio: audio, posterId: stringValue(payload["posterId"]) ?? currentPosterId)
    }

    private func handleAudioCleared(_ payload: [String: Any]) {
        let clearedPosterId = stringValue(payload["posterId"])

        if let clearedPosterId,
           clearedPosterId == currentPosterId {
            posterAudio = nil
        }

        guard clearedPosterId == nil || clearedPosterId == activeAudioPosterId else { return }
        stopAudio(resetPosterAttachment: clearedPosterId == nil || clearedPosterId == currentPosterId)
    }

    private func playAudio(audio: PosterAudioAttachment, posterId: String?) {
        let normalizedPosterId = posterId.map(OverrideSession.normalizedPosterID)

        if activeAudioURL == audio.url {
            activeAudioPosterId = normalizedPosterId
            currentAnthemTitle = audio.title
            isPlayingAnthem = true
            return
        }

        guard let source = PosterAudioSourceResolver.resolve(audio.url) else { return }
        configurePlaybackAudioSession()

        switch source {
        case let .direct(url):
            embeddedAudioPlayer.stop()
            let playerItem = AVPlayerItem(url: url)
            if audioPlayer == nil {
                audioPlayer = AVPlayer(playerItem: playerItem)
            } else {
                audioPlayer?.replaceCurrentItem(with: playerItem)
            }
            audioPlayer?.play()
        case .youtube, .spotify:
            audioPlayer?.pause()
            audioPlayer?.replaceCurrentItem(with: nil)
            embeddedAudioPlayer.play(source)
        }

        activeAudioURL = audio.url
        activeAudioPosterId = normalizedPosterId
        currentAnthemTitle = audio.title
        isPlayingAnthem = true
    }

    private func activateCurrentPosterAudioIfNeeded(force: Bool = false) {
        guard let audio = posterAudio else { return }
        guard force || activeAudioURL != audio.url else {
            activeAudioPosterId = currentPosterId.map(OverrideSession.normalizedPosterID)
            currentAnthemTitle = audio.title
            isPlayingAnthem = activeAudioURL != nil
            return
        }

        playAudio(audio: audio, posterId: currentPosterId)
    }

    private func stopAudio(resetPosterAttachment: Bool = true) {
        audioPlayer?.pause()
        audioPlayer?.replaceCurrentItem(with: nil)
        embeddedAudioPlayer.stop()
        activeAudioURL = nil
        activeAudioPosterId = nil
        isPlayingAnthem = false
        currentAnthemTitle = nil
        if resetPosterAttachment {
            posterAudio = nil
        }
    }

    // MARK: - Event Handlers

    private func applyDashboardState(_ payload: [String: Any]) {
        let source = dictionaryValue(payload["data"]) ?? payload
        let posters = OverrideSession.parsePosterList(from: source)
        guard !posters.isEmpty else { return }
        OverrideSession.shared.posters = posters
    }

    private func applyCanvasState(_ payload: [String: Any]) {
        let source = canvasSource(from: payload)
        currentPosterId = stringValue(source["posterId"]) ?? stringValue(payload["posterId"]) ?? currentPosterId

        if let layout = parseLayout(dictionaryValue(source["layout"]) ?? dictionaryValue(source["canvasLayout"]) ?? source) {
            currentLayout = layout
        }

        let audioPayload = dictionaryValue(source["audio"]) ?? dictionaryValue(source["posterAudio"]) ?? dictionaryValue(payload["audio"])
        posterAudio = parseAudio(audioPayload)
        if posterAudio != nil {
            activateCurrentPosterAudioIfNeeded()
        }

        let strokePayloads = objectArray(from: source, keys: ["strokes", "lines", "drawings"])
        if !strokePayloads.isEmpty {
            strokes = strokePayloads.compactMap(parseStroke)
        }

        let stickerPayloads = objectArray(from: source, keys: ["stickers", "assets", "gifs", "overlays"])
        if !stickerPayloads.isEmpty {
            stickers = stickerPayloads.compactMap(parseSticker)
        }

        applyTerritoryState(source)
        if source.keys != payload.keys {
            applyTerritoryState(payload)
        }
    }

    private func handleStrokeAdded(_ payload: [String: Any]) {
        let strokePayload = dictionaryValue(payload["stroke"]) ?? dictionaryValue(payload["data"]) ?? payload
        guard let stroke = parseStroke(strokePayload) else { return }
        upsert(stroke)
        applyTerritoryState(payload)
    }

    private func handleStickerAdded(_ payload: [String: Any]) {
        let stickerPayload = dictionaryValue(payload["sticker"]) ?? dictionaryValue(payload["data"]) ?? payload
        guard let sticker = parseSticker(stickerPayload) else { return }
        upsert(sticker)
        applyTerritoryState(payload)
    }

    private func handleStickerRemoved(_ payload: [String: Any]) {
        guard let stickerId = stringValue(payload["stickerId"]) ?? stringValue(payload["id"]) else { return }
        stickers.removeAll { $0.id == stickerId }
    }

    private func handleCanvasCleared(_ payload: [String: Any]) {
        if let posterId = stringValue(payload["posterId"]) {
            currentPosterId = posterId
        }
        resetTransientCanvasState(keepPosterId: true)
        canvasCleared = true
    }

    private func applyTerritoryState(_ payload: [String: Any]) {
        let source = territorySource(from: payload)

        if let owner = stringValue(source["owner"]) ?? stringValue(source["ownerTeamId"]) ?? stringValue(source["posterOwner"]) {
            posterOwner = owner
        }

        if let rawAreaPayload = dictionaryValue(source["rawArea"]) ?? dictionaryValue(source["area"]) {
            rawArea = parsePercentageMap(rawAreaPayload)
        }

        if let teamPayload = dictionaryValue(source["teams"]) ?? dictionaryValue(source["coverage"]) {
            let parsed = parsePercentageMap(teamPayload)
            if !parsed.isEmpty {
                territory = parsed
            }
        }
    }

    // MARK: - Parsing

    private var coordinateMeta: [String: Any] {
        [
            "coordinateSpace": "normalized",
            "origin": "top-left",
            "flipX": false,
            "flipY": false
        ]
    }

    private var layoutPayload: [String: Any] {
        [
            "width": currentLayout.width,
            "height": currentLayout.height,
            "aspectRatio": currentLayout.aspectRatio,
            "origin": currentLayout.origin
        ]
    }

    private func parseStroke(_ payload: [String: Any]) -> CanvasStroke? {
        let rawPoints = parsePoints(payload["points"])
        guard !rawPoints.isEmpty else { return nil }

        let teamId = stringValue(payload["teamId"]) ?? ""
        let userId = stringValue(payload["userId"]) ?? stringValue(payload["username"])
        let color = firstString(in: payload, keys: ["color", "strokeColor", "lineColor", "hexColor", "brushColor"]) ?? "#CAFB00"
        let points = rawPoints.map { normalize(point: $0) }

        let id = stringValue(payload["id"])
            ?? stringValue(payload["strokeId"])
            ?? syntheticStrokeID(teamId: teamId, userId: userId, color: color, points: points)

        return CanvasStroke(
            id: id,
            teamId: teamId,
            userId: userId,
            color: color,
            width: doubleValue(payload["width"]) ?? 8,
            points: points
        )
    }

    private func parseSticker(_ payload: [String: Any]) -> CanvasSticker? {
        guard let rawURL = firstString(in: payload, keys: ["url", "gifUrl", "imageUrl", "assetUrl", "src"]) else {
            return nil
        }

        let position = dictionaryValue(payload["position"]) ?? [:]
        let size = dictionaryValue(payload["size"]) ?? [:]
        let teamId = stringValue(payload["teamId"]) ?? ""

        let x = normalizeCoordinate(doubleValue(payload["x"]) ?? doubleValue(position["x"]) ?? 0, axis: .x)
        let y = normalizeCoordinate(doubleValue(payload["y"]) ?? doubleValue(position["y"]) ?? 0, axis: .y)

        let parsedWidth = normalizeSize(doubleValue(payload["width"]) ?? doubleValue(payload["w"]) ?? doubleValue(size["width"]) ?? 0.24, axis: .x)
        let parsedHeight = normalizeSize(doubleValue(payload["height"]) ?? doubleValue(payload["h"]) ?? doubleValue(size["height"]) ?? 0.24, axis: .y)

        let id = stringValue(payload["id"])
            ?? stringValue(payload["stickerId"])
            ?? syntheticStickerID(teamId: teamId, url: rawURL, x: x, y: y, width: parsedWidth, height: parsedHeight)

        return CanvasSticker(
            id: id,
            teamId: teamId,
            url: OverrideSession.resolvedURLString(rawURL),
            x: x,
            y: y,
            width: parsedWidth,
            height: parsedHeight,
            rotation: doubleValue(payload["rotation"]) ?? doubleValue(payload["angle"]) ?? 0
        )
    }

    private func parseLayout(_ payload: [String: Any]?) -> CanvasLayout? {
        guard let payload,
              let width = doubleValue(payload["width"]),
              let height = doubleValue(payload["height"]),
              height > 0 else {
            return nil
        }

        let aspectRatio = doubleValue(payload["aspectRatio"]) ?? (width / height)
        let origin = stringValue(payload["origin"]) ?? "top-left"
        return CanvasLayout(width: width, height: height, aspectRatio: aspectRatio, origin: origin)
    }

    private func parseAudio(_ payload: [String: Any]?) -> PosterAudioAttachment? {
        guard let payload,
              let rawURL = firstString(in: payload, keys: ["url", "audioUrl", "src"]) else {
            return nil
        }

        return PosterAudioAttachment(
            title: firstString(in: payload, keys: ["title", "name", "label"]) ?? "Poster Audio",
            url: OverrideSession.resolvedURLString(rawURL)
        )
    }

    private func parsePoints(_ rawValue: Any?) -> [CanvasPoint] {
        if let pointPayloads = rawValue as? [[String: Any]] {
            return pointPayloads.compactMap { point in
                guard let x = doubleValue(point["x"]),
                      let y = doubleValue(point["y"]) else {
                    return nil
                }
                return CanvasPoint(x: x, y: y)
            }
        }

        if let pointPairs = rawValue as? [[Double]] {
            return pointPairs.compactMap { pair in
                guard pair.count >= 2 else { return nil }
                return CanvasPoint(x: pair[0], y: pair[1])
            }
        }

        if let pointPairs = rawValue as? [[Any]] {
            return pointPairs.compactMap { pair in
                guard pair.count >= 2,
                      let x = doubleValue(pair[0]),
                      let y = doubleValue(pair[1]) else {
                    return nil
                }
                return CanvasPoint(x: x, y: y)
            }
        }

        return []
    }

    private enum CoordinateAxis {
        case x
        case y
    }

    private func normalize(point: CanvasPoint) -> CanvasPoint {
        CanvasPoint(
            x: normalizeCoordinate(point.x, axis: .x),
            y: normalizeCoordinate(point.y, axis: .y)
        )
    }

    private func normalizeCoordinate(_ value: Double, axis: CoordinateAxis) -> Double {
        let layoutDimension = axis == .x ? currentLayout.width : currentLayout.height
        let normalized = value > 1.0 && layoutDimension > 0 ? value / layoutDimension : value
        return min(max(normalized, 0), 1)
    }

    private func normalizeSize(_ value: Double, axis: CoordinateAxis) -> Double {
        guard value > 0 else { return 0.24 }
        let layoutDimension = axis == .x ? currentLayout.width : currentLayout.height
        let normalized = value > 1.0 && layoutDimension > 0 ? value / layoutDimension : value
        return min(max(normalized, 0.04), 1)
    }

    private func parsePercentageMap(_ payload: [String: Any]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: payload.compactMap { key, value in
            guard let amount = doubleValue(value) else { return nil }
            return (key, amount)
        })
    }

    private func doubleValue(_ rawValue: Any?) -> Double? {
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

    private func boolValue(_ rawValue: Any?) -> Bool? {
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

    private func stringValue(_ rawValue: Any?) -> String? {
        switch rawValue {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private func intValue(_ rawValue: Any?) -> Int? {
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

    private func dictionaryValue(_ rawValue: Any?) -> [String: Any]? {
        rawValue as? [String: Any]
    }

    private func firstString(in payload: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = stringValue(payload[key]), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func objectArray(from payload: [String: Any], keys: [String]) -> [[String: Any]] {
        for key in keys {
            if let array = payload[key] as? [[String: Any]] {
                return array
            }
        }

        for wrapper in ["data", "state", "canvas"] {
            if let nested = payload[wrapper] as? [String: Any] {
                let array = objectArray(from: nested, keys: keys)
                if !array.isEmpty {
                    return array
                }
            }
        }

        return []
    }

    private func canvasSource(from payload: [String: Any]) -> [String: Any] {
        if let canvas = dictionaryValue(payload["canvas"]) {
            return canvasSource(from: canvas)
        }

        if let state = dictionaryValue(payload["state"]) {
            return canvasSource(from: state)
        }

        if let data = dictionaryValue(payload["data"]) {
            if data["strokes"] != nil || data["stickers"] != nil || data["layout"] != nil || data["audio"] != nil {
                return data
            }
            return canvasSource(from: data)
        }

        return payload
    }

    private func territorySource(from payload: [String: Any]) -> [String: Any] {
        if let territory = dictionaryValue(payload["territory"]) {
            return territory
        }

        if let coverage = dictionaryValue(payload["coverage"]) {
            return coverage
        }

        if let data = dictionaryValue(payload["data"]) {
            if data["territory"] != nil || data["teams"] != nil || data["rawArea"] != nil {
                return territorySource(from: data)
            }
        }

        return payload
    }

    private func syntheticStrokeID(teamId: String, userId: String?, color: String, points: [CanvasPoint]) -> String {
        guard let first = points.first, let last = points.last else {
            return "stroke-\(UUID().uuidString)"
        }

        return [
            "stroke",
            teamId,
            userId ?? "anon",
            color,
            String(points.count),
            coordinateToken(first.x),
            coordinateToken(first.y),
            coordinateToken(last.x),
            coordinateToken(last.y)
        ].joined(separator: "-")
    }

    private func syntheticStickerID(teamId: String, url: String, x: Double, y: Double, width: Double, height: Double) -> String {
        [
            "sticker",
            teamId,
            OverrideSession.resolvedURLString(url),
            coordinateToken(x),
            coordinateToken(y),
            coordinateToken(width),
            coordinateToken(height)
        ].joined(separator: "-")
    }

    private func coordinateToken(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private func socketURL(transport: String, sid: String? = nil) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }

        let trimmedBasePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = trimmedBasePath.isEmpty ? "/socket.io/" : "/\(trimmedBasePath)/socket.io/"

        var queryItems = [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: transport),
            URLQueryItem(name: "t", value: timestampToken())
        ]

        if let sid {
            queryItems.append(URLQueryItem(name: "sid", value: sid))
        }

        components.queryItems = queryItems
        return components.url
    }

    private func webSocketURL() -> URL? {
        guard var components = URLComponents(string: base) else { return nil }

        switch components.scheme?.lowercased() {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        default:
            components.scheme = "ws"
        }

        let trimmedBasePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = trimmedBasePath.isEmpty ? "/socket.io/" : "/\(trimmedBasePath)/socket.io/"
        components.queryItems = [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket"),
            URLQueryItem(name: "t", value: timestampToken())
        ]
        return components.url
    }

    private func timestampToken() -> String {
        String(Int(Date().timeIntervalSince1970 * 1000))
    }

    private func configurePlaybackAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("[Audio] Failed to reconfigure AVAudioSession: \(error.localizedDescription)")
        }
    }

    private func connectWebSocket() async -> Bool {
        guard let url = webSocketURL() else { return false }

        let task = transportSession.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        do {
            let openPacket = try await withTimeout(seconds: 15) {
                try await self.receiveTextMessage(from: task)
            }
            guard let sessionId = parseOpenPacket(openPacket) else {
                throw SocketClientError.malformedOpenPacket
            }

            sid = sessionId
            isConnected = true
            namespaceConnected = false
            didSendNamespaceConnect = false
            transportMode = .webSocket
            connectionState = .syncing
            startWebSocketReceiveLoop(task)
            _ = await sendNamespaceConnectPacket()
            return true
        } catch {
            webSocketReceiveTask?.cancel()
            webSocketReceiveTask = nil
            task.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            sid = nil
            isConnected = false
            transportMode = nil
            return false
        }
    }

    private func startWebSocketReceiveLoop(_ task: URLSessionWebSocketTask) {
        webSocketReceiveTask?.cancel()
        webSocketReceiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let packet = try await self?.receiveTextMessage(from: task)
                    guard let packet else { return }
                    await self?.handleInboundPacket(packet)
                } catch {
                    guard !Task.isCancelled else { return }
                    await self?.handleWebSocketFailure(error)
                    return
                }
            }
        }
    }

    private func receiveTextMessage(from task: URLSessionWebSocketTask) async throws -> String {
        let message = try await task.receive()
        switch message {
        case let .string(text):
            return text
        case let .data(data):
            guard let text = String(data: data, encoding: .utf8) else {
                throw SocketClientError.unsupportedMessage
            }
            return text
        @unknown default:
            throw SocketClientError.unsupportedMessage
        }
    }

    private func parseOpenPacket(_ packet: String) -> String? {
        guard packet.hasPrefix("0"),
              let jsonStart = packet.firstIndex(of: "{"),
              let json = try? JSONSerialization.jsonObject(with: Data(packet[jsonStart...].utf8)) as? [String: Any] else {
            return nil
        }

        return stringValue(json["sid"])
    }

    private func handleWebSocketFailure(_ error: Error) async {
        setFailure("Socket websocket failed for \(base): \(error.localizedDescription)")
        await recoverConnectionIfPossible(reason: "Socket websocket connection dropped")
    }

    private func recoverConnectionIfPossible(reason: String) async {
        guard !isRecoveringConnection else { return }
        guard let posterId = currentPosterId,
              let teamId = currentTeamId,
              let username = currentUsername else {
            disconnect()
            return
        }

        isRecoveringConnection = true
        defer { isRecoveringConnection = false }

        connectionErrorMessage = "\(reason). Reconnecting..."
        disconnect()
        connectionState = .connecting

        guard await connect() else { return }
        await joinPoster(posterId: posterId, teamId: teamId, userId: currentUserId, username: username)
    }

    private func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw SocketClientError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - State Helpers

    private func upsert(_ stroke: CanvasStroke) {
        if let index = strokes.firstIndex(where: { $0.id == stroke.id }) {
            strokes[index] = stroke
        } else {
            strokes.append(stroke)
        }
    }

    private func upsert(_ sticker: CanvasSticker) {
        if let index = stickers.firstIndex(where: { $0.id == sticker.id }) {
            stickers[index] = sticker
        } else {
            stickers.append(sticker)
        }
    }

    private func resetTransientCanvasState(keepPosterId: Bool = false, preservePlaybackState: Bool = false) {
        strokes = []
        stickers = []
        territory = [:]
        rawArea = [:]
        posterOwner = nil
        posterAudio = nil
        if !preservePlaybackState {
            currentAnthemTitle = nil
            isPlayingAnthem = false
            activeAudioPosterId = nil
            activeAudioURL = nil
        }
        currentLayout = .a4Portrait
        canvasCleared = false
        if !keepPosterId {
            currentPosterId = nil
        }
    }

    private func setFailure(_ message: String) {
        connectionErrorMessage = message
        connectionState = .failed
    }

    private func requestJSON(path: String) async -> [String: Any]? {
        guard let url = URL(string: "\(base)\(path)") else {
            setFailure("HTTP URL is invalid for \(path)")
            return nil
        }

        do {
            let (data, response) = try await transportSession.data(from: url)
            if let http = response as? HTTPURLResponse,
               !(200 ..< 300).contains(http.statusCode) {
                setFailure("HTTP \(http.statusCode) while loading \(path) from \(base)")
                return nil
            }

            guard let payload = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                setFailure("HTTP payload for \(path) from \(base) was not recognized")
                return nil
            }

            connectionErrorMessage = nil
            return payload
        } catch {
            setFailure("HTTP request failed for \(path) on \(base): \(error.localizedDescription)")
            return nil
        }
    }
}
