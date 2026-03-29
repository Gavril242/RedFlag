import SwiftUI
import Combine
import RealityKit
import ARKit

enum RedFlagPalette {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.055)
    static let surface = Color(red: 0.102, green: 0.102, blue: 0.102)
    static let surfaceHigh = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let surfaceLow = Color(red: 0.075, green: 0.075, blue: 0.075)
    static let surfaceHighest = Color(red: 0.18, green: 0.18, blue: 0.18)
    static let primary = Color(red: 0.953, green: 1.0, blue: 0.792)
    static let primaryContainer = Color(red: 0.792, green: 0.992, blue: 0.0)
    static let primaryDim = Color(red: 0.745, green: 0.933, blue: 0.0)
    static let secondary = Color(red: 1.0, green: 0.42, blue: 0.608)
    static let tertiary = Color(red: 0.675, green: 0.537, blue: 1.0)
    static let outline = Color(red: 0.462, green: 0.459, blue: 0.459)
    static let outlineVariant = Color(red: 0.282, green: 0.282, blue: 0.278)
    static let textPrimary = Color.white
    static let textMuted = Color(red: 0.678, green: 0.667, blue: 0.667)
    static let success = Color(red: 0.36, green: 0.95, blue: 0.61)
}

enum RedFlagFont {
    static func headline(_ size: CGFloat) -> Font {
        .custom("HelveticaNeue-CondensedBlack", size: size)
    }

    static func body(_ size: CGFloat) -> Font {
        .custom("AvenirNext-Medium", size: size)
    }

    static func bodyBold(_ size: CGFloat) -> Font {
        .custom("AvenirNext-DemiBold", size: size)
    }

    static func label(_ size: CGFloat) -> Font {
        .custom("Menlo-Bold", size: size)
    }
}

enum RedFlagTab: String, CaseIterable, Identifiable {
    case scan
    case intel
    case posters
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scan: return "SCAN"
        case .intel: return "INTEL"
        case .posters: return "POSTERS"
        case .profile: return "PROFILE"
        }
    }

    var icon: String {
        switch self {
        case .scan: return "viewfinder"
        case .intel: return "map.fill"
        case .posters: return "square.grid.2x2.fill"
        case .profile: return "person.fill"
        }
    }

    var accent: Color {
        switch self {
        case .scan: return RedFlagPalette.primaryContainer
        case .intel: return RedFlagPalette.primary
        case .posters: return RedFlagPalette.tertiary
        case .profile: return RedFlagPalette.secondary
        }
    }
}

enum SprayColorOption: String, CaseIterable, Identifiable {
    case lime = "LIME"
    case pink = "PINK"
    case ultra = "ULTRA"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .lime: return RedFlagPalette.primaryContainer
        case .pink: return RedFlagPalette.secondary
        case .ultra: return RedFlagPalette.tertiary
        }
    }
}

enum FeedAccent {
    case primary
    case secondary
    case tertiary

    var color: Color {
        switch self {
        case .primary: return RedFlagPalette.primaryContainer
        case .secondary: return RedFlagPalette.secondary
        case .tertiary: return RedFlagPalette.tertiary
        }
    }
}

struct SectorControl: Identifiable {
    let id = UUID()
    let code: String
    let name: String
    var control: Int
}

struct Battlefront: Identifiable {
    let id = UUID()
    let title: String
    let threat: String
    var friendlyControl: Double
    var remainingSeconds: Int
}

struct FeedEvent: Identifiable {
    let id = UUID()
    let timestamp: String
    let message: String
    let accent: FeedAccent
}

struct ExtractItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let accent: Color
    let symbol: String
}

struct FeedPreviewCard: Identifiable {
    let id = UUID()
    let label: String
    let title: String
    let message: String
    let accent: Color
    let symbol: String
}

@MainActor
final class RedFlagSimulator: ObservableObject {
    @Published var promptText = "Hyper-detailed neon wolf mural with toxic lime drips and electric blue eyes."
    @Published var previewTitle = "Cyber Wolf"
    @Published var previewUUID = "882-VX-PROTOTYPE"
    @Published var previewSubtitle = "Synth-ink sticker ready for deployment"
    @Published var energyLevel = 0.84
    @Published var selectedSpray: SprayColorOption = .lime
    @Published var brushRadius = 42.0
    @Published var latencyMS = 38
    @Published var teamXP = 8400 // Changed to Int
    @Published var squadName = "OVERRIDE_PROTOCL"
    @Published var nodeName = "SHIBUYA_03"
    @Published var friendlyFaction = "VOID_RUNNERS"
    @Published var rivalFaction = "NEON_CLAN"
    @Published var friendlyOwnership = 0.64
    @Published var rivalOwnership = 0.36
    @Published var postersOwned = 14
    @Published var rivalsExpelled = 52
    @Published var anthemProgress = 0.73
    @Published var unityBridgeStatus = "SIM READY"
    @Published var selectedPoster = "SECTOR_7_WALL"
    @Published var sectors: [SectorControl] = [
        SectorControl(code: "0x8F2", name: "THE_STACKS", control: 84),
        SectorControl(code: "0x4A1", name: "NEON_GUTTER", control: 62),
        SectorControl(code: "0x22C", name: "DRONE_PORT", control: 100)
    ]
    @Published var battles: [Battlefront] = [
        Battlefront(title: "ROOFTOP_VANDAL", threat: "HIGH", friendlyControl: 0.42, remainingSeconds: 203),
        Battlefront(title: "GRID_SQUAT", threat: "MED", friendlyControl: 0.58, remainingSeconds: 164)
    ]
    @Published var feed: [FeedEvent] = [
        FeedEvent(timestamp: "09:44", message: "USER_404 DEPLOYED ANCHOR AT SHIBUYA_XING", accent: .primary),
        FeedEvent(timestamp: "09:42", message: "RIVAL_CLAN CAPTURED STATION_6", accent: .secondary),
        FeedEvent(timestamp: "09:39", message: "SYSTEM_OVERRIDE DETECTED IN SECTOR_08", accent: .tertiary)
    ]
    @Published var extracts: [ExtractItem] = [
        ExtractItem(title: "Pink_Crown.v2", subtitle: "Neon authority tag", accent: RedFlagPalette.secondary, symbol: "crown.fill"),
        ExtractItem(title: "Chrome_Core", subtitle: "Metallic biomech mark", accent: RedFlagPalette.primaryContainer, symbol: "heart.fill"),
        ExtractItem(title: "Ghost_Stencil", subtitle: "Phantom wall bite", accent: RedFlagPalette.tertiary, symbol: "eye.fill")
    ]
    @Published var liveFeedCards: [FeedPreviewCard] = [
        FeedPreviewCard(label: "Capture // 04:12", title: "Sector 4 Baseline", message: "New stencil detected. Rival Phantom expelled.", accent: RedFlagPalette.secondary, symbol: "camera.fill"),
        FeedPreviewCard(label: "System // 03:55", title: "Territory Sync", message: "8 new posters detected in High-Rise district.", accent: RedFlagPalette.primaryContainer, symbol: "map.fill"),
        FeedPreviewCard(label: "Alert // 02:20", title: "Hardware Breach", message: "Uplink attempted from unidentified node.", accent: RedFlagPalette.tertiary, symbol: "antenna.radiowaves.left.and.right")
    ]

    func tick() {
        energyLevel = clamp(energyLevel + Double.random(in: -0.03 ... 0.015), lower: 0.41, upper: 0.97)
        brushRadius = clamp(brushRadius + Double.random(in: -4 ... 3), lower: 16, upper: 72)
        latencyMS = Int(clamp(Double(latencyMS) + Double.random(in: -6 ... 8), lower: 18, upper: 92))

        let swing = Double.random(in: -0.03 ... 0.028)
        friendlyOwnership = clamp(friendlyOwnership + swing, lower: 0.34, upper: 0.77)
        rivalOwnership = 1 - friendlyOwnership

        for index in sectors.indices {
            let delta = Int.random(in: -4 ... 3)
            sectors[index].control = Int(clamp(Double(sectors[index].control + delta), lower: 34, upper: 100))
        }

        for index in battles.indices {
            battles[index].friendlyControl = clamp(battles[index].friendlyControl + Double.random(in: -0.06 ... 0.05), lower: 0.18, upper: 0.82)
            let nextRemaining = battles[index].remainingSeconds - Int.random(in: 4 ... 9)
            battles[index].remainingSeconds = nextRemaining > 0 ? nextRemaining : Int.random(in: 110 ... 280)
        }

        if Int.random(in: 0 ... 2) == 0 {
            appendFeed(message: randomFeedMessage(), accent: [.primary, .secondary, .tertiary].randomElement() ?? .primary)
        }
    }

    func selectSpray(_ spray: SprayColorOption) {
        selectedSpray = spray
        appendFeed(message: "BRUSH PROFILE SHIFTED TO \(spray.rawValue)", accent: accent(for: spray))
    }

    func performGenerate() {
        let sanitized = promptText
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let titleTokens = Array(sanitized.prefix(2))
        if titleTokens.isEmpty {
            previewTitle = "Neon Relic"
        } else {
            previewTitle = titleTokens.joined(separator: " ")
        }

        previewUUID = "\(Int.random(in: 110 ... 999))-\(String(["VX", "NX", "OVR", "TAG"].randomElement() ?? "VX"))-\(["PROTO", "ALPHA", "BETA", "SYNC"].randomElement() ?? "PROTO")"
        previewSubtitle = "\(selectedSpray.rawValue) overlay staged for \(selectedPoster)"
        energyLevel = clamp(energyLevel - 0.125, lower: 0.22, upper: 0.97)

        extracts.insert(
            ExtractItem(
                title: previewTitle.replacingOccurrences(of: " ", with: "_"),
                subtitle: "Generated from operator prompt",
                accent: selectedSpray.color,
                symbol: selectedSpray == .pink ? "sparkles" : "scribble"
            ),
            at: 0
        )

        if extracts.count > 4 {
            extracts.removeLast()
        }

        appendFeed(message: "AI TAG GENERATED FOR \(selectedPoster)", accent: accent(for: selectedSpray))
    }

    func performStick() {
        postersOwned += 1
        friendlyOwnership = clamp(friendlyOwnership + 0.018, lower: 0.34, upper: 0.84)
        rivalOwnership = 1 - friendlyOwnership
        appendFeed(message: "STICKER DEPLOYED TO \(selectedPoster)", accent: accent(for: selectedSpray))
    }

    func cycleBridgeStatus() {
        let states = ["SIM READY", "UNITY LINK", "TRACKED", "SYNC MOCK"]
        if let currentIndex = states.firstIndex(of: unityBridgeStatus) {
            unityBridgeStatus = states[(currentIndex + 1) % states.count]
        } else {
            unityBridgeStatus = states[0]
        }
    }

    func battleCountdown(_ battle: Battlefront) -> String {
        let minutes = battle.remainingSeconds / 60
        let seconds = battle.remainingSeconds % 60
        return String(format: "%02d:%02d REMAINING", minutes, seconds)
    }

    private func appendFeed(message: String, accent: FeedAccent) {
        feed.insert(FeedEvent(timestamp: currentTimestamp(), message: message, accent: accent), at: 0)
        if feed.count > 6 {
            feed.removeLast()
        }
    }

    private func randomFeedMessage() -> String {
        [
            "SYNC PULSE CONFIRMED AT DRONE_PORT",
            "UNITY GHOST PREVIEW REFRESHED",
            "RIVAL SIGNAL LOST IN SECTOR_11",
            "HAPTIC BURST QUEUED FOR CONFLICT EVENT",
            "POSTER SIGNATURE VERIFIED FOR SHIBUYA_XING"
        ].randomElement() ?? "NETWORK GHOST DETECTED"
    }

    private func accent(for spray: SprayColorOption) -> FeedAccent {
        switch spray {
        case .lime: return .primary
        case .pink: return .secondary
        case .ultra: return .tertiary
        }
    }

    private func currentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}

struct CutCornerShape: Shape {
    var cut: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: cut, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: cut))
        path.closeSubpath()
        return path
    }
}

enum PanelAccentSide {
    case leading
    case trailing

    var alignment: Alignment {
        switch self {
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }
}

struct GridBackdrop: View {
    var spacing: CGFloat = 34
    var lineColor: Color = RedFlagPalette.outlineVariant.opacity(0.5)

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                var path = Path()

                stride(from: 0, through: size.width, by: spacing).forEach { x in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }

                stride(from: 0, through: size.height, by: spacing).forEach { y in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }

                context.stroke(path, with: .color(lineColor), lineWidth: 0.65)
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [RedFlagPalette.background.opacity(0.12), .clear],
                    startPoint: .top,
                    endPoint: .bottom)
                .frame(height: geometry.size.height * 0.24)
            }
        }
        .allowsHitTesting(false)
    }
}

struct HUDPanel<Content: View>: View {
    var accent: Color = RedFlagPalette.primaryContainer
    var accentSide: PanelAccentSide = .leading
    private let content: Content

    init(accent: Color = RedFlagPalette.primaryContainer,
         accentSide: PanelAccentSide = .leading,
         @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.accentSide = accentSide
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                CutCornerShape(cut: 20)
                    .fill(RedFlagPalette.surface.opacity(0.92))
            )
            .overlay(
                CutCornerShape(cut: 20)
                    .stroke(accent.opacity(0.18), lineWidth: 1)
            )
            .overlay(alignment: accentSide.alignment) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 4)
                    .padding(10)
            }
            .shadow(color: accent.opacity(0.18), radius: 18, x: 0, y: 8)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    var foreground: Color = Color.white

    var body: some View {
        Text(text)
            .font(RedFlagFont.label(10))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(color)
            )
    }
}

struct SectionHeader: View {
    let title: String
    var accent: Color = RedFlagPalette.primaryContainer
    var trailingText: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(RedFlagFont.headline(22))
                .foregroundStyle(accent)
                .textCase(.uppercase)

            Rectangle()
                .fill(RedFlagPalette.outlineVariant.opacity(0.55))
                .frame(height: 1)

            if let trailingText {
                Text(trailingText)
                    .font(RedFlagFont.label(10))
                    .foregroundStyle(RedFlagPalette.textMuted)
            }
        }
    }
}

struct NeonMeter: View {
    let progress: Double
    let accent: Color
    var background: Color = RedFlagPalette.surfaceHighest
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(background)

                Rectangle()
                    .fill(accent)
                    .frame(width: geometry.size.width * progress)
                    .shadow(color: accent.opacity(0.5), radius: 10, x: 0, y: 0)
            }
        }
        .frame(height: height)
        .clipShape(Rectangle())
    }
}

struct SignalDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.9), radius: 8)
    }
}

// Missing HUD components from ContentView scope
struct ARTechSurface: View {
    var body: some View {
        Group {
            if ARWorldTrackingConfiguration.isSupported {
                ARCameraRepresentable()
            } else {
                FallbackARSurface()
            }
        }
    }
}

struct FallbackARSurface: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [RedFlagPalette.surfaceLow, RedFlagPalette.background, RedFlagPalette.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GridBackdrop(spacing: 38, lineColor: RedFlagPalette.outlineVariant.opacity(0.45))

            Image(systemName: "camera.aperture")
                .font(.system(size: 84, weight: .black))
                .foregroundStyle(RedFlagPalette.primaryContainer.opacity(0.5))
        }
    }
}

struct ARCameraRepresentable: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic

        if let referenceImages = ARReferenceImage.referenceImages(inGroupNamed: "AR_Posters", bundle: nil),
           !referenceImages.isEmpty {
            configuration.detectionImages = referenceImages
            configuration.maximumNumberOfTrackedImages = min(referenceImages.count, 4)
        }

        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        context.coordinator.installPreviewAnchorIfNeeded()

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.installPreviewAnchorIfNeeded()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        weak var arView: ARView?
        private var previewAnchorInstalled = false

        func installPreviewAnchorIfNeeded() {
            guard let arView, !previewAnchorInstalled else { return }

            previewAnchorInstalled = true

            let mesh = MeshResource.generateBox(width: 0.22, height: 0.14, depth: 0.002, cornerRadius: 0.01)
            let material = UnlitMaterial(color: UIColor(red: 0.792, green: 0.992, blue: 0.0, alpha: 0.35))
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = .zero

            var transform = matrix_identity_float4x4
            transform.columns.3.z = -0.75

            let anchor = AnchorEntity(world: transform)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            guard let arView else { return }

            for anchor in anchors {
                guard let imageAnchor = anchor as? ARImageAnchor else { continue }

                let width = Float(imageAnchor.referenceImage.physicalSize.width)
                let height = Float(imageAnchor.referenceImage.physicalSize.height)

                let mesh = MeshResource.generateBox(width: width, height: height, depth: 0.003, cornerRadius: 0.008)
                let material = UnlitMaterial(color: UIColor(red: 1.0, green: 0.42, blue: 0.608, alpha: 0.32))
                let overlay = ModelEntity(mesh: mesh, materials: [material])
                overlay.position.z = 0.0015

                let trackedAnchor = AnchorEntity(anchor: imageAnchor)
                trackedAnchor.addChild(overlay)

                DispatchQueue.main.async {
                    arView.scene.addAnchor(trackedAnchor)
                }
            }
        }
    }
}

struct ScanCornerDecorations: View {
    var body: some View {
        GeometryReader { geometry in
            let topY = 106.0
            let bottomY = geometry.size.height - 176.0

            Group {
                corner.position(x: 36, y: topY)
                corner.scaleEffect(x: -1, y: 1).position(x: geometry.size.width - 36, y: topY)
                corner.scaleEffect(x: 1, y: -1).position(x: 36, y: bottomY)
                corner.scaleEffect(x: -1, y: -1).position(x: geometry.size.width - 36, y: bottomY)
            }
        }
        .allowsHitTesting(false)
    }

    private var corner: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 32))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 32, y: 0))
        }
        .stroke(RedFlagPalette.primaryContainer, lineWidth: 2)
        .frame(width: 32, height: 32)
    }
}

struct PosterGhost: View {
    let title: String
    let subtitle: String
    let accent: Color
    let icon: String

    var body: some View {
        ZStack {
            CutCornerShape(cut: 18)
                .fill(accent.opacity(0.14))
                .overlay(
                    CutCornerShape(cut: 18)
                        .stroke(accent.opacity(0.45), lineWidth: 2)
                )

            LinearGradient(
                colors: [accent.opacity(0.28), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(CutCornerShape(cut: 18))

            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(accent)

                Text(title).font(RedFlagFont.headline(26)).foregroundStyle(accent)
                Rectangle().fill(accent).frame(height: 2)
                Text(subtitle).font(RedFlagFont.label(11)).foregroundStyle(accent.opacity(0.92))
            }
            .padding(18)
        }
    }
}

struct ReticleView: View {
    var body: some View {
        ZStack {
            Rectangle().stroke(RedFlagPalette.primaryContainer.opacity(0.3), lineWidth: 1).frame(width: 168, height: 168)
            Rectangle().stroke(RedFlagPalette.primaryContainer.opacity(0.16), lineWidth: 1).frame(width: 210, height: 210)
            Rectangle().fill(RedFlagPalette.primaryContainer).frame(width: 8, height: 8)

            VStack {
                Text("ANALYZING...")
                    .font(RedFlagFont.label(9))
                    .foregroundStyle(RedFlagPalette.background)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RedFlagPalette.primaryContainer)
                Spacer()
            }
            .frame(width: 168, height: 168)
        }
    }
}

struct TerritoryMapPanel: View {
    @ObservedObject var simulator: RedFlagSimulator
    var body: some View {
        HUDPanel(accent: RedFlagPalette.primaryContainer) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TERRITORY_WAR_MAP").font(RedFlagFont.headline(30))
                        Text("SCANNING...").font(RedFlagFont.label(10)).foregroundStyle(RedFlagPalette.textMuted)
                    }
                    Spacer()
                    StatusPill(text: "LIVE", color: RedFlagPalette.secondary)
                }
                Rectangle().fill(RedFlagPalette.surfaceLow).frame(height: 200).overlay(Text("MAP VISUALIZER").foregroundStyle(RedFlagPalette.textMuted))
            }
        }
    }
}

struct FeedOverlayPanel: View {
    @ObservedObject var simulator: RedFlagSimulator
    var body: some View {
        HUDPanel(accent: RedFlagPalette.tertiary) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Global Feed", accent: RedFlagPalette.textPrimary, trailingText: "WEBSOCKET")
                ForEach(simulator.feed) { event in
                    Text("[\(event.timestamp)] \(event.message)").font(RedFlagFont.bodyBold(12)).foregroundStyle(RedFlagPalette.textPrimary)
                }
            }
        }
    }
}
