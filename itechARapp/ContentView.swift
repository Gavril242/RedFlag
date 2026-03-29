import SwiftUI
import RealityKit
import ARKit
import UIKit
import Combine
import WebKit

// MARK: - Helpers

struct IdentifiableString: Identifiable { let id: String }

struct PlacedSticker: Identifiable {
    let id = UUID()
    let type: String
    let position: CGPoint
}

// MARK: - Native GIF via WKWebView

struct NativeGIFView: UIViewRepresentable {
    let gifNameOrURL: String

    final class Coordinator {
        var loadedSource = ""
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.isUserInteractionEnabled = false
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.layer.backgroundColor = UIColor.clear.cgColor
        wv.scrollView.backgroundColor = .clear
        wv.isUserInteractionEnabled = false
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let resolvedValue = OverrideSession.resolvedURLString(gifNameOrURL)

        if (resolvedValue.hasPrefix("http://") || resolvedValue.hasPrefix("https://")),
           let url = URL(string: resolvedValue) {
            let html = """
            <!doctype html>
            <html>
            <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
            <style>
            html, body {
              margin: 0;
              padding: 0;
              width: 100%;
              height: 100%;
              overflow: hidden;
              background: transparent !important;
            }
            body {
              display: flex;
              align-items: center;
              justify-content: center;
            }
            img {
              width: 100%;
              height: 100%;
              object-fit: contain;
              background: transparent !important;
              pointer-events: none;
              user-select: none;
            }
            </style>
            </head>
            <body>
              <img src="\(escapedHTML(resolvedValue))" />
            </body>
            </html>
            """

            if context.coordinator.loadedSource != resolvedValue {
                context.coordinator.loadedSource = resolvedValue
                uiView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
            }
        } else if let url = Bundle.main.url(forResource: gifNameOrURL, withExtension: "gif"),
                  let data = try? Data(contentsOf: url) {
            if context.coordinator.loadedSource != gifNameOrURL {
                context.coordinator.loadedSource = gifNameOrURL
                uiView.load(data, mimeType: "image/gif", characterEncodingName: "UTF-8", baseURL: url.deletingLastPathComponent())
            }
        } else {
            let html = "<body style='margin:0;padding:0;background:transparent;display:flex;justify-content:center;align-items:center;'><h1 style='color:magenta;font-family:courier;border:1px solid magenta;padding:10px;'>GIF</h1></body>"
            if context.coordinator.loadedSource != "__fallback__\(gifNameOrURL)" {
                context.coordinator.loadedSource = "__fallback__\(gifNameOrURL)"
                uiView.loadHTMLString(html, baseURL: nil)
            }
        }
    }

    private func escapedHTML(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Hex Color Helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var simulator = RedFlagSimulator()
    @StateObject private var session = OverrideSession.shared
    @State private var selectedTab: RedFlagTab = .scan
    @State private var showUnityEditor = false

    private let timer = Timer.publish(every: 3.2, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            RedFlagPalette.background.ignoresSafeArea()
            if !session.isLoggedIn || !session.hasTeam {
                AuthFlowView(session: session)
            } else {
                mainContent
                    .safeAreaInset(edge: .top) {
                        GlobalTopBar(simulator: simulator, selectedTab: selectedTab, openEditor: { showUnityEditor = true })
                    }
                    .safeAreaInset(edge: .bottom) {
                        BottomNavigationBar(selectedTab: $selectedTab)
                    }
                    .fullScreenCover(isPresented: $showUnityEditor) {
                        UnityOverrideEditorView(simulator: simulator)
                    }
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(timer) { _ in simulator.tick() }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch selectedTab {
        case .scan:    ScanScreen(simulator: simulator, openEditor: { showUnityEditor = true })
        case .intel:   IntelScreen(simulator: simulator)
        case .posters: PostersGalleryView(simulator: simulator)
        case .profile: ProfileView(simulator: simulator)
        }
    }
}

// MARK: - Auth Flow (Login / Register + Team)

struct AuthFlowView: View {
    @ObservedObject var session: OverrideSession
    @State private var username = ""
    @State private var password = ""
    @State private var isRegisterMode = false

    var body: some View {
        ZStack {
            RedFlagPalette.background.ignoresSafeArea()
            GridBackdrop().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 60)

                    Text("OVERRIDE_PROTOCOL").font(RedFlagFont.headline(36)).foregroundStyle(RedFlagPalette.primaryContainer)
                    Text(session.isLoggedIn ? "SELECT FACTION" : "IDENTIFY YOURSELF")
                        .font(RedFlagFont.label(11)).foregroundStyle(RedFlagPalette.textMuted)

                    BackendServerPanel(session: session, accent: RedFlagPalette.tertiary, actionLabel: "UPDATE SERVER") {
                        await session.fetchPosters()
                        if session.isLoggedIn {
                            await session.fetchTeams()
                        }
                    }
                    .padding(.horizontal, 24)

                    // Auth form (only if not yet logged in)
                    if !session.isLoggedIn {
                        HUDPanel(accent: RedFlagPalette.primaryContainer) {
                            VStack(spacing: 14) {
                                TextField("OPERATOR_USERNAME", text: $username)
                                    .font(RedFlagFont.body(16))
                                    .foregroundStyle(RedFlagPalette.textPrimary)
                                    .padding(12)
                                    .background(RedFlagPalette.surfaceHigh)
                                    .clipShape(CutCornerShape(cut: 8))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)

                                SecureField("PASSWORD", text: $password)
                                    .font(RedFlagFont.body(16))
                                    .foregroundStyle(RedFlagPalette.textPrimary)
                                    .padding(12)
                                    .background(RedFlagPalette.surfaceHigh)
                                    .clipShape(CutCornerShape(cut: 8))

                                if let err = session.errorMessage {
                                    Text(err).font(RedFlagFont.label(10)).foregroundStyle(RedFlagPalette.secondary)
                                }

                                Button {
                                    guard !username.isEmpty, !password.isEmpty else { return }
                                    Task {
                                        if isRegisterMode {
                                            await session.register(username: username, password: password)
                                        } else {
                                            await session.login(username: username, password: password)
                                        }
                                        if session.isLoggedIn {
                                            await session.fetchTeams()
                                        }
                                    }
                                } label: {
                                    Group {
                                        if session.isLoading {
                                            ProgressView().tint(.black)
                                        } else {
                                            Text(isRegisterMode ? "REGISTER" : "ENTER THE GRID")
                                                .font(RedFlagFont.label(12)).foregroundStyle(.black)
                                        }
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(CutCornerShape(cut: 12).fill(RedFlagPalette.primaryContainer))
                                }

                                Button {
                                    isRegisterMode.toggle()
                                    session.errorMessage = nil
                                } label: {
                                    Text(isRegisterMode ? "ALREADY HAVE ACCESS? LOGIN" : "NEW OPERATOR? REGISTER")
                                        .font(RedFlagFont.label(10)).foregroundStyle(RedFlagPalette.textMuted)
                                }
                            }
                        }.padding(.horizontal, 24)
                    }

                    // Team selection (shown after login, before team is set)
                    if session.isLoggedIn && !session.hasTeam {
                        TeamFlowView(session: session)
                    }

                    Spacer(minLength: 60)
                }
            }
        }
    }
}

// MARK: - Team Flow (Create / Join)

struct TeamFlowView: View {
    @ObservedObject var session: OverrideSession
    @State private var newTeamName = ""
    @State private var showCreate = false

    var body: some View {
        VStack(spacing: 16) {
            // Create team option
            HUDPanel(accent: RedFlagPalette.secondary) {
                VStack(spacing: 12) {
                    if showCreate {
                        TextField("TEAM NAME", text: $newTeamName)
                            .font(RedFlagFont.body(16))
                            .foregroundStyle(RedFlagPalette.textPrimary)
                            .padding(12)
                            .background(RedFlagPalette.surfaceHigh)
                            .clipShape(CutCornerShape(cut: 8))
                            .autocorrectionDisabled()

                        Button {
                            guard !newTeamName.isEmpty else { return }
                            Task { await session.createTeam(name: newTeamName) }
                        } label: {
                            Text("DEPLOY FACTION").font(RedFlagFont.label(12)).foregroundStyle(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(CutCornerShape(cut: 10).fill(RedFlagPalette.secondary))
                        }
                    } else {
                        Button {
                            showCreate = true
                        } label: {
                            Text("+ CREATE NEW FACTION").font(RedFlagFont.label(12)).foregroundStyle(RedFlagPalette.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                    }
                }
            }.padding(.horizontal, 24)

            if let err = session.errorMessage {
                Text(err).font(RedFlagFont.label(10)).foregroundStyle(RedFlagPalette.secondary).padding(.horizontal, 24)
            }

            // Existing teams to join
            if !session.availableTeams.isEmpty {
                Text("OR JOIN EXISTING").font(RedFlagFont.label(11)).foregroundStyle(RedFlagPalette.textMuted)
                ForEach(session.availableTeams) { team in
                    Button {
                        Task { await session.joinTeam(teamId: team.id) }
                    } label: {
                        HStack {
                            Text(team.name.uppercased()).font(RedFlagFont.bodyBold(14))
                            Spacer()
                            Text("\(team.memberCount ?? 0) MEMBERS").font(RedFlagFont.label(10)).foregroundStyle(RedFlagPalette.textMuted)
                        }
                        .padding(12)
                        .background(CutCornerShape(cut: 10).fill(RedFlagPalette.surface))
                        .overlay(CutCornerShape(cut: 10).stroke(RedFlagPalette.outlineVariant, lineWidth: 1))
                    }
                    .foregroundStyle(RedFlagPalette.textPrimary)
                    .padding(.horizontal, 24)
                }
            }
        }
        .task { await session.fetchTeams() }
    }
}


// MARK: - Posters Gallery

struct PostersGalleryView: View {
    @ObservedObject var simulator: RedFlagSimulator
    @StateObject private var session = OverrideSession.shared
    @State private var selectedPoster: IdentifiableString?

    private var fallbackPosterID: String {
        OverrideSession.normalizedPosterID(simulator.selectedPoster)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HeaderSection(title: "ARCHIVE", subtitle: "SCANNED OVERRIDES")
                if session.posters.isEmpty {
                    HUDPanel(accent: RedFlagPalette.tertiary) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("NO POSTERS SYNCED")
                                .font(RedFlagFont.headline(18))
                                .foregroundStyle(RedFlagPalette.textPrimary)

                            Text("Pull the real poster rooms from the backend before opening the editor.")
                                .font(RedFlagFont.body(14))
                                .foregroundStyle(RedFlagPalette.textMuted)

                            if let errorMessage = session.errorMessage {
                                Text(errorMessage)
                                    .font(RedFlagFont.label(9))
                                    .foregroundStyle(RedFlagPalette.secondary)
                            }

                            Button {
                                Task { await session.fetchPosters() }
                            } label: {
                                Text("REFRESH POSTERS")
                                    .font(RedFlagFont.label(10))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(CutCornerShape(cut: 10).fill(RedFlagPalette.primaryContainer))
                            }

                            Button {
                                selectPoster(fallbackPosterID)
                            } label: {
                                Text("OPEN CURRENT ROOM")
                                    .font(RedFlagFont.label(10))
                                    .foregroundStyle(RedFlagPalette.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(CutCornerShape(cut: 10).fill(RedFlagPalette.surfaceHigh))
                            }
                            .disabled(fallbackPosterID.isEmpty)
                        }
                    }
                    BackendServerPanel(session: session, accent: RedFlagPalette.tertiary, actionLabel: "REFRESH SERVER") {
                        await session.fetchPosters()
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 20) {
                        ForEach(session.posters) { poster in
                            PosterCard(id: poster.id) { selectPoster(poster.id) }
                        }
                    }
                }
            }.padding(20)
        }
        .sheet(item: $selectedPoster) { item in
            RemoteCanvasEditor(posterID: item.id, simulator: simulator)
        }
        .task {
            await session.fetchPosters()
            if OverrideSession.isPlaceholderPosterID(simulator.selectedPoster),
               let firstPosterId = session.posters.first?.id {
                simulator.selectedPoster = firstPosterId
            }
        }
    }

    private func selectPoster(_ posterID: String) {
        let resolvedPosterID = OverrideSession.normalizedPosterID(posterID)
        simulator.selectedPoster = resolvedPosterID
        selectedPoster = IdentifiableString(id: resolvedPosterID)
    }
}

enum PosterEditorMode: String, CaseIterable, Identifiable {
    case draw = "DRAW"
    case sticker = "STICKER"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .draw: return "pencil.and.scribble"
        case .sticker: return "face.smiling"
        }
    }
}

// MARK: - Remote Canvas Editor

struct RemoteCanvasEditor: View {
    let posterID: String
    @ObservedObject var simulator: RedFlagSimulator
    @StateObject private var socket = OverrideSocketClient.shared
    @StateObject private var session = OverrideSession.shared
    @Environment(\.dismiss) var dismiss

    @State private var currentStrokePoints: [CGPoint] = []
    @State private var optimisticStrokes: [CanvasStroke] = []
    @State private var optimisticStickers: [CanvasSticker] = []
    @State private var editorMode: PosterEditorMode = .draw
    @State private var stickerAssets: [OverrideStickerAsset] = OverrideSession.fallbackStickerLibrary
    @State private var selectedSticker: OverrideStickerAsset?
    @State private var isReloading = false
    @State private var customStickerURL = ""
    @State private var audioTitle = ""
    @State private var audioURL = ""
    @State private var isSavingAudio = false
    @State private var isTriggeringAudio = false
    @State private var isClearingAudio = false

    private var resolvedPosterID: String {
        OverrideSession.normalizedPosterID(posterID)
    }

    private var canvasWidth: CGFloat {
        min(UIScreen.main.bounds.width - 40, 360)
    }

    private var canvasHeight: CGFloat {
        let aspectRatio = max(CGFloat(socket.currentLayout.aspectRatio), 0.1)
        return canvasWidth / aspectRatio
    }

    private var teamColor: Color {
        switch session.team?.id {
        case "red":  return RedFlagPalette.secondary
        case "blue": return RedFlagPalette.tertiary
        default:     return RedFlagPalette.primaryContainer
        }
    }

    private var activeUserID: String {
        session.player?.id ?? session.player?.username ?? "Ghost"
    }

    private var activeUsername: String {
        session.player?.username ?? "Ghost"
    }

    private var connectionPillColor: Color {
        switch socket.connectionState {
        case .live:
            return RedFlagPalette.success
        case .failed:
            return RedFlagPalette.secondary
        case .connecting, .syncing:
            return RedFlagPalette.textMuted
        case .disconnected:
            return RedFlagPalette.outlineVariant
        }
    }

    private var connectionIssue: String? {
        socket.connectionErrorMessage ?? session.errorMessage
    }

    private var renderedStrokes: [CanvasStroke] {
        socket.strokes + optimisticStrokes.filter { optimisticStroke in
            !socket.strokes.contains(where: { matches($0, optimisticStroke) })
        }
    }

    private var renderedStickers: [CanvasSticker] {
        socket.stickers + optimisticStickers.filter { optimisticSticker in
            !socket.stickers.contains(where: { matches($0, optimisticSticker) })
        }
    }

    var body: some View {
        ZStack {
            RedFlagPalette.background.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("REMOTE OVERRIDE").font(RedFlagFont.label(10)).foregroundStyle(RedFlagPalette.secondary)
                        Text(resolvedPosterID.uppercased()).font(RedFlagFont.headline(24))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let owner = socket.posterOwner {
                            Text("OWNER \(owner.uppercased())")
                                .font(RedFlagFont.label(9))
                                .foregroundStyle(RedFlagPalette.textMuted)
                        }
                        if let teamID = session.team?.id,
                           let coverage = socket.rawArea[teamID] ?? socket.territory[teamID] {
                            Text("YOUR COVERAGE \(displayPercent(coverage))%")
                                .font(RedFlagFont.label(9))
                                .foregroundStyle(teamColor)
                        }
                        StatusPill(text: socket.connectionState.rawValue, color: connectionPillColor)
                    }
                    Button("DONE") { dismiss() }
                        .font(RedFlagFont.bodyBold(14)).padding(.horizontal).padding(.vertical, 10)
                        .background(CutCornerShape(cut: 10).fill(RedFlagPalette.primaryContainer))
                        .foregroundStyle(.black)
                }
                .padding(.horizontal)

                PosterCanvasBoard(
                    strokes: renderedStrokes,
                    stickers: renderedStickers,
                    previewPoints: currentStrokePoints,
                    previewColor: teamColor,
                    previewWidth: 10,
                    size: CGSize(width: canvasWidth, height: canvasHeight)
                )
                .frame(width: canvasWidth, height: canvasHeight)
                .clipShape(CutCornerShape(cut: 20))
                .overlay(CutCornerShape(cut: 20).stroke(teamColor.opacity(0.4), lineWidth: 2))
                .contentShape(Rectangle())
                .highPriorityGesture(editorGesture)

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ForEach(PosterEditorMode.allCases) { mode in
                            Button {
                                editorMode = mode
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: mode.icon)
                                    Text(mode.rawValue)
                                }
                                .font(RedFlagFont.label(11))
                                .foregroundStyle(editorMode == mode ? .black : RedFlagPalette.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    CutCornerShape(cut: 10)
                                        .fill(editorMode == mode ? RedFlagPalette.primaryContainer : RedFlagPalette.surfaceHigh)
                                )
                            }
                        }

                        Button {
                            Task { await reloadCanvas() }
                        } label: {
                            Image(systemName: isReloading ? "arrow.trianglehead.2.clockwise.rotate.90" : "arrow.clockwise")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 52, height: 48)
                                .background(CutCornerShape(cut: 10).fill(RedFlagPalette.secondary))
                        }
                        .disabled(isReloading)
                    }

                    if let issue = connectionIssue {
                        Text(issue)
                            .font(RedFlagFont.label(9))
                            .foregroundStyle(RedFlagPalette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("SERVER \(session.serverURL)")
                        .font(RedFlagFont.label(8))
                        .foregroundStyle(RedFlagPalette.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)

                    if connectionIssue != nil {
                        BackendServerPanel(session: session, accent: RedFlagPalette.tertiary, actionLabel: "RECONNECT") {
                            await reconnectEditor()
                        }
                    }

                    if editorMode == .sticker {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("GIF PACK + STICKERS")
                                .font(RedFlagFont.label(9))
                                .foregroundStyle(RedFlagPalette.textMuted)

                            StickerLibraryStrip(
                                stickers: stickerAssets,
                                selectedSticker: selectedSticker,
                                onSelect: { asset in
                                    selectedSticker = asset
                                    customStickerURL = asset.url
                                }
                            )

                            EditorInputField(
                                label: "CUSTOM GIF / STICKER URL",
                                text: $customStickerURL,
                                placeholder: "https://media.giphy.com/.../giphy.gif",
                                keyboardType: .URL
                            )

                            HStack(spacing: 10) {
                                Button {
                                    useCustomStickerURL()
                                } label: {
                                    Text("USE URL")
                                        .font(RedFlagFont.label(10))
                                        .foregroundStyle(.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(CutCornerShape(cut: 10).fill(RedFlagPalette.primaryContainer))
                                }

                                Button {
                                    customStickerURL = ""
                                } label: {
                                    Text("CLEAR")
                                        .font(RedFlagFont.label(10))
                                        .foregroundStyle(RedFlagPalette.textPrimary)
                                        .frame(width: 86)
                                        .padding(.vertical, 12)
                                        .background(CutCornerShape(cut: 10).fill(RedFlagPalette.surfaceHigh))
                                }
                            }
                        }
                    }

                    HStack(spacing: 16) {
                        ColorPickerRow(simulator: simulator)
                        Spacer()
                        if let sticker = selectedSticker, editorMode == .sticker {
                            Text(sticker.name.uppercased())
                                .font(RedFlagFont.label(9))
                                .foregroundStyle(RedFlagPalette.textMuted)
                        } else {
                            Text("DRAG TO DRAW")
                                .font(RedFlagFont.label(9))
                                .foregroundStyle(RedFlagPalette.textMuted)
                        }
                    }

                    HUDPanel(accent: socket.isPlayingAnthem ? RedFlagPalette.secondary : RedFlagPalette.tertiary) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("POSTER AUDIO")
                                        .font(RedFlagFont.headline(18))
                                        .foregroundStyle(RedFlagPalette.textPrimary)
                                    Text(socket.posterAudio?.title ?? "NO TRACK ATTACHED")
                                        .font(RedFlagFont.label(9))
                                        .foregroundStyle(RedFlagPalette.textMuted)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if socket.isPlayingAnthem {
                                    StatusPill(text: "PLAYING", color: RedFlagPalette.secondary)
                                } else if socket.posterAudio != nil {
                                    StatusPill(text: "READY", color: RedFlagPalette.success)
                                } else {
                                    StatusPill(text: "OFF", color: RedFlagPalette.outlineVariant)
                                }
                            }

                            EditorInputField(
                                label: "AUDIO TITLE",
                                text: $audioTitle,
                                placeholder: "Team Anthem"
                            )

                            EditorInputField(
                                label: "AUDIO URL",
                                text: $audioURL,
                                placeholder: "https://example.com/song.mp3 or https://www.youtube.com/watch?v=...",
                                keyboardType: .URL
                            )

                            Text("Best results: direct audio files. YouTube / YouTube Music watch links also play through a hidden embed. Spotify links are less reliable on iOS.")
                                .font(RedFlagFont.label(9))
                                .foregroundStyle(RedFlagPalette.textMuted)

                            HStack(spacing: 10) {
                                Button {
                                    Task { await savePosterAudio() }
                                } label: {
                                    Text(isSavingAudio ? "SAVING..." : "SAVE")
                                        .font(RedFlagFont.label(10))
                                        .foregroundStyle(.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(CutCornerShape(cut: 10).fill(RedFlagPalette.primaryContainer))
                                }
                                .disabled(isSavingAudio || isTriggeringAudio || isClearingAudio)

                                Button {
                                    Task { await playPosterAudio() }
                                } label: {
                                    Text(isTriggeringAudio ? "PLAYING..." : "PLAY")
                                        .font(RedFlagFont.label(10))
                                        .foregroundStyle(.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(CutCornerShape(cut: 10).fill(RedFlagPalette.secondary))
                                }
                                .disabled(isSavingAudio || isTriggeringAudio || isClearingAudio || (socket.posterAudio == nil && audioURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

                                Button {
                                    Task { await clearPosterAudio() }
                                } label: {
                                    Text(isClearingAudio ? "CLEARING..." : "CLEAR")
                                        .font(RedFlagFont.label(10))
                                        .foregroundStyle(RedFlagPalette.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(CutCornerShape(cut: 10).fill(RedFlagPalette.surfaceHigh))
                                }
                                .disabled(isSavingAudio || isTriggeringAudio || isClearingAudio || socket.posterAudio == nil)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
        }
        .task {
            await reconnectEditor()
        }
    }

    private var editorGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard editorMode == .draw else { return }
                currentStrokePoints.append(clamped(value.location))
            }
            .onEnded { value in
                let point = clamped(value.location)

                if editorMode == .draw {
                    currentStrokePoints.append(point)
                    sendStroke()
                    currentStrokePoints = []
                } else {
                    Task { await placeSticker(at: point) }
                }
            }
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x), canvasWidth),
            y: min(max(0, point.y), canvasHeight)
        )
    }

    private func displayPercent(_ value: Double) -> Int {
        let normalized = value <= 1.0 ? value * 100 : value
        return Int(normalized.rounded())
    }

    private func reloadCanvas() async {
        isReloading = true
        await socket.reloadPosterState(posterId: resolvedPosterID)
        isReloading = false
    }

    private func sendStroke() {
        guard !currentStrokePoints.isEmpty else { return }
        let normalizedPoints = currentStrokePoints.map { p in
            (Double(p.x / canvasWidth), Double(p.y / canvasHeight))
        }
        let colorHex: String
        switch simulator.selectedSpray {
        case .lime:  colorHex = "#CAFB00"
        case .pink:  colorHex = "#FF6B9B"
        case .ultra: colorHex = "#AC89FF"
        }

        let optimisticStroke = CanvasStroke(
            id: "local-stroke-\(UUID().uuidString)",
            teamId: session.team?.id ?? "red",
            userId: activeUserID,
            color: colorHex,
            width: 8,
            points: normalizedPoints.map { CanvasPoint(x: $0.0, y: $0.1) }
        )
        optimisticStrokes.append(optimisticStroke)

        Task {
            let didSend = await socket.emitStroke(
                posterId: resolvedPosterID,
                teamId: session.team?.id ?? "red",
                userId: activeUserID,
                username: activeUsername,
                color: colorHex,
                width: 8,
                points: normalizedPoints
            )
            if didSend {
                try? await Task.sleep(nanoseconds: 350_000_000)
                await socket.reloadPosterState(posterId: resolvedPosterID)
            }
        }
    }

    private func placeSticker(at point: CGPoint) async {
        let trimmedCustomURL = customStickerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let sticker = selectedSticker ?? (!trimmedCustomURL.isEmpty ? OverrideStickerAsset(name: "Custom GIF", url: OverrideSession.resolvedURLString(trimmedCustomURL)) : nil)
        guard let sticker else { return }

        let normalizedX = Double(point.x / canvasWidth)
        let normalizedY = Double(point.y / canvasHeight)
        let resolvedURL = OverrideSession.resolvedURLString(sticker.url)

        optimisticStickers.append(
            CanvasSticker(
                id: "local-sticker-\(UUID().uuidString)",
                teamId: session.team?.id ?? "red",
                url: resolvedURL,
                x: normalizedX,
                y: normalizedY,
                width: 0.24,
                height: 0.24,
                rotation: 0
            )
        )

        let didSend = await socket.emitSticker(
            posterId: resolvedPosterID,
            teamId: session.team?.id ?? "red",
            userId: activeUserID,
            username: activeUsername,
            url: resolvedURL,
            x: normalizedX,
            y: normalizedY,
            w: 0.24,
            h: 0.24
        )

        if didSend {
            try? await Task.sleep(nanoseconds: 350_000_000)
            await socket.reloadPosterState(posterId: resolvedPosterID)
        }
    }

    private func useCustomStickerURL() {
        let trimmedURL = customStickerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }

        let resolvedURL = OverrideSession.resolvedURLString(trimmedURL)
        selectedSticker = OverrideStickerAsset(name: "Custom GIF", url: resolvedURL)
        customStickerURL = resolvedURL
        editorMode = .sticker
    }

    private func savePosterAudio() async {
        isSavingAudio = true
        defer { isSavingAudio = false }

        guard let audio = await session.attachPosterAudio(
            posterId: resolvedPosterID,
            title: audioTitle,
            urlString: audioURL
        ) else { return }

        socket.posterAudio = audio
        audioTitle = audio.title
        audioURL = audio.url
    }

    private func playPosterAudio() async {
        isTriggeringAudio = true
        defer { isTriggeringAudio = false }

        var previewAudio = socket.posterAudio

        if socket.posterAudio == nil,
           let attachedAudio = await session.attachPosterAudio(
                posterId: resolvedPosterID,
                title: audioTitle,
                urlString: audioURL
           ) {
            socket.posterAudio = attachedAudio
            audioTitle = attachedAudio.title
            audioURL = attachedAudio.url
            previewAudio = attachedAudio
        }

        if let audio = await session.triggerPosterAudio(posterId: resolvedPosterID) {
            socket.previewAudio(audio, posterId: resolvedPosterID)
            audioTitle = audio.title
            audioURL = audio.url
        } else if let previewAudio {
            socket.previewAudio(previewAudio, posterId: resolvedPosterID)
        }
    }

    private func clearPosterAudio() async {
        isClearingAudio = true
        defer { isClearingAudio = false }

        guard await session.clearPosterAudio(posterId: resolvedPosterID) else { return }
        socket.clearAudioState()
        audioTitle = session.team?.anthemTitle ?? "Team Anthem"
        audioURL = session.team?.anthemUrl ?? ""
    }

    private func reconnectEditor() async {
        guard !resolvedPosterID.isEmpty else { return }

        simulator.selectedPoster = resolvedPosterID
        optimisticStrokes = []
        optimisticStickers = []

        _ = await socket.connect()
        await socket.joinPoster(
            posterId: resolvedPosterID,
            teamId: session.team?.id ?? "red",
            userId: session.player?.id,
            username: activeUsername
        )

        let library = await session.fetchStickerLibrary()
        stickerAssets = library

        if let selectedSticker, library.contains(selectedSticker) {
            self.selectedSticker = selectedSticker
        } else if !customStickerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            useCustomStickerURL()
        } else {
            selectedSticker = library.first
            customStickerURL = library.first?.url ?? ""
        }

        audioTitle = socket.posterAudio?.title ?? session.team?.anthemTitle ?? "Team Anthem"
        audioURL = socket.posterAudio?.url ?? session.team?.anthemUrl ?? ""
    }

    private func matches(_ lhs: CanvasStroke, _ rhs: CanvasStroke) -> Bool {
        lhs.teamId == rhs.teamId &&
        lhs.userId == rhs.userId &&
        lhs.color.lowercased() == rhs.color.lowercased() &&
        abs(lhs.width - rhs.width) < 0.001 &&
        lhs.points == rhs.points
    }

    private func matches(_ lhs: CanvasSticker, _ rhs: CanvasSticker) -> Bool {
        lhs.teamId == rhs.teamId &&
        lhs.url == rhs.url &&
        abs(lhs.x - rhs.x) < 0.002 &&
        abs(lhs.y - rhs.y) < 0.002 &&
        abs(lhs.width - rhs.width) < 0.002 &&
        abs(lhs.height - rhs.height) < 0.002 &&
        abs(lhs.rotation - rhs.rotation) < 0.5
    }
}

struct PosterCanvasBoard: View {
    let strokes: [CanvasStroke]
    let stickers: [CanvasSticker]
    let previewPoints: [CGPoint]
    let previewColor: Color
    let previewWidth: CGFloat
    let size: CGSize

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .overlay(GridBackdrop(spacing: 20, lineColor: .white.opacity(0.05)))

            Canvas { context, canvasSize in
                for stroke in strokes {
                    let mappedPoints = stroke.points.map { point in
                        CGPoint(x: point.x * canvasSize.width, y: point.y * canvasSize.height)
                    }

                    if mappedPoints.count == 1, let first = mappedPoints.first {
                        let radius = max(2, CGFloat(stroke.width) / 2)
                        let rect = CGRect(x: first.x - radius, y: first.y - radius, width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(Color(hex: stroke.color)))
                    } else if let first = mappedPoints.first {
                        var path = Path()
                        path.move(to: first)
                        mappedPoints.dropFirst().forEach { path.addLine(to: $0) }
                        context.stroke(path, with: .color(Color(hex: stroke.color)), lineWidth: CGFloat(stroke.width))
                    }
                }

                if previewPoints.count == 1, let point = previewPoints.first {
                    let radius = max(3, previewWidth / 2)
                    let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(previewColor))
                } else if let first = previewPoints.first {
                    var path = Path()
                    path.move(to: first)
                    previewPoints.dropFirst().forEach { path.addLine(to: $0) }
                    context.stroke(path, with: .color(previewColor), lineWidth: previewWidth)
                }
            }

            ZStack {
                ForEach(stickers) { sticker in
                    NativeGIFView(gifNameOrURL: sticker.url)
                        .frame(width: CGFloat(sticker.width) * size.width, height: CGFloat(sticker.height) * size.height)
                        .rotationEffect(.degrees(sticker.rotation))
                        .position(x: CGFloat(sticker.x) * size.width, y: CGFloat(sticker.y) * size.height)
                }
            }
            .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
    }
}

struct StickerLibraryStrip: View {
    let stickers: [OverrideStickerAsset]
    let selectedSticker: OverrideStickerAsset?
    let onSelect: (OverrideStickerAsset) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(stickers) { asset in
                    Button {
                        onSelect(asset)
                    } label: {
                        VStack(spacing: 8) {
                            NativeGIFView(gifNameOrURL: asset.url)
                                .frame(width: 68, height: 68)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            Text(asset.name.uppercased())
                                .font(RedFlagFont.label(8))
                                .foregroundStyle(RedFlagPalette.textPrimary)
                                .lineLimit(1)
                        }
                        .padding(8)
                        .frame(width: 94)
                        .background(
                            CutCornerShape(cut: 10)
                                .fill(selectedSticker?.id == asset.id ? RedFlagPalette.surfaceHighest : RedFlagPalette.surfaceHigh)
                        )
                        .overlay(
                            CutCornerShape(cut: 10)
                                .stroke(selectedSticker?.id == asset.id ? RedFlagPalette.primaryContainer : RedFlagPalette.outlineVariant, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

struct EditorInputField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(RedFlagFont.label(9))
                .foregroundStyle(RedFlagPalette.textMuted)

            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(RedFlagPalette.textMuted.opacity(0.7)))
                .font(RedFlagFont.body(14))
                .foregroundStyle(RedFlagPalette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(keyboardType)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(CutCornerShape(cut: 10).fill(RedFlagPalette.surfaceHigh))
                .overlay(CutCornerShape(cut: 10).stroke(RedFlagPalette.outlineVariant, lineWidth: 1))
        }
    }
}

struct BackendServerPanel: View {
    @ObservedObject var session: OverrideSession
    var accent: Color = RedFlagPalette.tertiary
    var actionLabel = "APPLY SERVER"
    var onApply: (() async -> Void)? = nil

    @State private var draftURL = ""
    @State private var isApplying = false

    var body: some View {
        HUDPanel(accent: accent) {
            VStack(alignment: .leading, spacing: 10) {
                Text("BACKEND ROUTE")
                    .font(RedFlagFont.headline(16))
                    .foregroundStyle(RedFlagPalette.textPrimary)

                Text("Use the active Xcode/server endpoint for posters, stickers, GIFs, audio, and Unity sync.")
                    .font(RedFlagFont.label(8))
                    .foregroundStyle(RedFlagPalette.textMuted)

                EditorInputField(
                    label: "API SERVER",
                    text: $draftURL,
                    placeholder: "http://192.168.1.10:3000",
                    keyboardType: .URL
                )

                HStack(spacing: 10) {
                    Button {
                        applyServerURL(resetToDefault: false)
                    } label: {
                        Text(isApplying ? "SYNCING..." : actionLabel)
                            .font(RedFlagFont.label(10))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(CutCornerShape(cut: 10).fill(RedFlagPalette.primaryContainer))
                    }
                    .disabled(isApplying)

                    Button {
                        applyServerURL(resetToDefault: true)
                    } label: {
                        Text("RESET")
                            .font(RedFlagFont.label(10))
                            .foregroundStyle(RedFlagPalette.textPrimary)
                            .frame(width: 92)
                            .padding(.vertical, 12)
                            .background(CutCornerShape(cut: 10).fill(RedFlagPalette.surfaceHigh))
                    }
                    .disabled(isApplying)
                }
            }
        }
        .onAppear {
            if draftURL.isEmpty {
                draftURL = session.serverURL
            }
        }
        .onChange(of: session.serverURL) { newValue in
            if !isApplying {
                draftURL = newValue
            }
        }
    }

    private func applyServerURL(resetToDefault: Bool) {
        Task {
            isApplying = true
            defer { isApplying = false }

            if resetToDefault {
                session.resetServerURL()
            } else {
                session.updateServerURL(draftURL)
            }

            draftURL = session.serverURL
            await onApply?()
        }
    }
}

// MARK: - Shared UI Components

struct ActionButton: View {
    let icon: String; let label: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(RedFlagFont.label(8))
            }
            .foregroundStyle(RedFlagPalette.primaryContainer)
            .frame(width: 60, height: 60)
            .background(CutCornerShape(cut: 10).fill(RedFlagPalette.surfaceHigh))
        }
    }
}

struct PosterCard: View {
    let id: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RedFlagPalette.surfaceHigh
                    Image(systemName: "doc.text.image.fill").font(.system(size: 40)).foregroundStyle(RedFlagPalette.tertiary.opacity(0.5))
                }.frame(height: 160).clipShape(CutCornerShape(cut: 15))
                Text(id.uppercased()).font(RedFlagFont.bodyBold(14)).foregroundStyle(RedFlagPalette.textPrimary)
            }
        }
    }
}

struct GlobalTopBar: View {
    @ObservedObject var simulator: RedFlagSimulator
    let selectedTab: RedFlagTab
    let openEditor: () -> Void
    var body: some View {
        HStack {
            Text(OverrideSession.shared.team?.name ?? simulator.squadName)
                .font(RedFlagFont.headline(15)).foregroundStyle(RedFlagPalette.primaryContainer)
            Spacer()
            Text(selectedTab.title).font(RedFlagFont.headline(18)).padding(.horizontal).padding(.vertical, 4)
                .background(CutCornerShape(cut: 8).fill(RedFlagPalette.surface))
            Spacer()
            Button(action: openEditor) {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.black).frame(width: 32, height: 32)
                    .background(CutCornerShape(cut: 10).fill(RedFlagPalette.secondary))
            }
        }.padding().background(RedFlagPalette.background.opacity(0.9).ignoresSafeArea())
    }
}

struct BottomNavigationBar: View {
    @Binding var selectedTab: RedFlagTab
    var body: some View {
        HStack(spacing: 0) {
            ForEach(RedFlagTab.allCases) { tab in
                Button { selectedTab = tab } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon).font(.system(size: 20, weight: .black))
                        Text(tab.title).font(RedFlagFont.label(9))
                    }
                    .foregroundStyle(selectedTab == tab ? tab.accent : RedFlagPalette.textMuted)
                    .frame(maxWidth: .infinity)
                }
            }
        }.padding(.top, 12).padding(.bottom, 30).background(RedFlagPalette.surface.ignoresSafeArea())
    }
}

struct ProfileView: View {
    @ObservedObject var simulator: RedFlagSimulator
    var body: some View {
        VStack {
            HeaderSection(title: "IDENTITY", subtitle: OverrideSession.shared.player?.username.uppercased() ?? "OPERATOR_01")
            Spacer()
            Image(systemName: "person.text.rectangle.fill").font(.system(size: 100)).foregroundStyle(RedFlagPalette.primary)
            Text("TEAM: \(OverrideSession.shared.team?.name.uppercased() ?? "UNASSIGNED")").font(RedFlagFont.headline(28))
            Text("LEVEL \(simulator.teamXP / 100)").font(RedFlagFont.headline(40))
            Spacer()
        }.padding()
    }
}

struct HeaderSection: View {
    let title: String; let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(RedFlagFont.headline(34)).foregroundStyle(RedFlagPalette.textPrimary)
            Text(subtitle).font(RedFlagFont.label(11)).foregroundStyle(RedFlagPalette.primaryContainer)
        }
    }
}

struct ScanScreen: View {
    @ObservedObject var simulator: RedFlagSimulator; let openEditor: () -> Void
    var body: some View {
        ZStack {
            ARTechSurface().ignoresSafeArea()
            VStack {
                Spacer()
                HUDPanel(accent: RedFlagPalette.primaryContainer) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("UNITY 6 AR ENGINE").font(RedFlagFont.headline(18))
                            Spacer()
                            StatusPill(text: "READY", color: RedFlagPalette.secondary)
                        }
                        Button(action: openEditor) {
                            Text("LAUNCH OVERRIDE INTERFACE").font(RedFlagFont.label(11)).foregroundStyle(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(CutCornerShape(cut: 12).fill(RedFlagPalette.secondary))
                        }
                    }
                }.padding(.horizontal, 20).padding(.bottom, 100)
            }
        }
    }
}

struct IntelScreen: View {
    @ObservedObject var simulator: RedFlagSimulator
    var body: some View {
        ScrollView {
            VStack(spacing: 20) { TerritoryMapPanel(simulator: simulator); FeedOverlayPanel(simulator: simulator) }.padding()
        }
    }
}

struct UnityOverrideEditorView: View {
    @ObservedObject var simulator: RedFlagSimulator
    @StateObject private var socket = OverrideSocketClient.shared
    @StateObject private var session = OverrideSession.shared
    @Environment(\.dismiss) private var dismiss
    @State private var remoteEditorPoster: IdentifiableString?

    private var manualPosterID: String? {
        let posterID = OverrideSession.normalizedPosterID(simulator.selectedPoster)
        return posterID.isEmpty ? nil : posterID
    }

    private var resolvedPosterID: String? {
        let selectedPoster = OverrideSession.normalizedPosterID(simulator.selectedPoster)
        if !OverrideSession.isPlaceholderPosterID(selectedPoster) {
            return selectedPoster
        }
        return session.posters.first?.id
    }

    private var editorLaunchPosterID: String? {
        resolvedPosterID ?? session.posters.first?.id ?? manualPosterID
    }

    var body: some View {
        ZStack {
            UnityViewRepresentable()
                .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 50, height: 50)
                            .background(CutCornerShape(cut: 12).fill(RedFlagPalette.primaryContainer))
                    }

                    Spacer()

                    if socket.isPlayingAnthem {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note.list")
                            Text("NOW PLAYING: \(socket.currentAnthemTitle ?? "Anthem")")
                                .font(RedFlagFont.label(10))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 50)
                        .background(.thinMaterial)
                        .clipShape(CutCornerShape(cut: 8))
                        .foregroundStyle(.white)
                    }

                    Spacer()

                    Button(action: openRemoteEditor) {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                            Text("EDITOR")
                        }
                        .font(RedFlagFont.label(12))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .background(CutCornerShape(cut: 12).fill(RedFlagPalette.secondary))
                    }
                    .disabled(editorLaunchPosterID == nil)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                HStack {
                    Text((resolvedPosterID ?? "WAITING FOR ROOM").uppercased())
                        .font(RedFlagFont.label(10))
                        .foregroundStyle(RedFlagPalette.textMuted)

                    Spacer()

                    if let owner = socket.posterOwner {
                        Text("OWNER \(owner.uppercased())")
                            .font(RedFlagFont.label(10))
                            .foregroundStyle(RedFlagPalette.primaryContainer)
                    }
                }
                .padding(.horizontal, 20)

                Spacer()

                HUDPanel(accent: RedFlagPalette.tertiary, accentSide: .trailing) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("TRACKED POSTER VIEW")
                                    .font(RedFlagFont.headline(18))
                                    .foregroundStyle(RedFlagPalette.textPrimary)
                                Text("Unity keeps the AR-locked canvas. Use the editor for precise GIF, sticker, and audio changes.")
                                    .font(RedFlagFont.body(13))
                                    .foregroundStyle(RedFlagPalette.textMuted)
                            }

                            Spacer()

                            StatusPill(text: "UNITY LIVE", color: RedFlagPalette.success)
                        }

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("STICKERS \(socket.stickers.count)")
                                    .font(RedFlagFont.label(10))
                                    .foregroundStyle(RedFlagPalette.textPrimary)

                                Text(socket.posterAudio?.title ?? "NO AUDIO ATTACHED")
                                    .font(RedFlagFont.label(9))
                                    .foregroundStyle(RedFlagPalette.textMuted)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button(action: openRemoteEditor) {
                                Text("OPEN POSTER EDITOR")
                                    .font(RedFlagFont.label(10))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(CutCornerShape(cut: 10).fill(RedFlagPalette.primaryContainer))
                            }
                            .disabled(editorLaunchPosterID == nil)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .sheet(item: $remoteEditorPoster) { item in
            RemoteCanvasEditor(posterID: item.id, simulator: simulator)
        }
        .task(id: resolvedPosterID ?? "") {
            await session.fetchPosters()
            guard let resolvedPosterID else { return }
            simulator.selectedPoster = resolvedPosterID
            await socket.connect()
            await socket.joinPoster(
                posterId: resolvedPosterID,
                teamId: session.team?.id ?? "red",
                userId: session.player?.id,
                username: session.player?.username ?? "Ghost"
            )
        }
    }

    private func openRemoteEditor() {
        if let editorLaunchPosterID {
            remoteEditorPoster = IdentifiableString(id: editorLaunchPosterID)
        }
    }
}

struct ColorPickerRow: View {
    @ObservedObject var simulator: RedFlagSimulator
    var body: some View {
        HStack(spacing: 15) {
            ForEach(SprayColorOption.allCases) { spray in
                Circle().fill(spray.color).frame(width: 35, height: 35)
                    .overlay(Circle().stroke(Color.white, lineWidth: simulator.selectedSpray == spray ? 2 : 0))
                    .onTapGesture { simulator.selectedSpray = spray }
            }
        }
    }
}

#Preview { ContentView() }
