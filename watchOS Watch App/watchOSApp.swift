import SwiftUI
import WatchConnectivity
import WatchKit

@main
struct watchOS_Watch_App: App {
    @StateObject private var mirror = WatchMirror()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            WatchMirrorScreen(mirror: mirror)
                .onChange(of: phase) { if $0 == .active { mirror.refresh() } }
        }
    }
}

struct MirrorTurn: Identifiable {
    let id: String
    let role: String
    let text: String
}

final class WatchMirror: NSObject, ObservableObject, WCSessionDelegate {
    @Published var messages: [MirrorTurn] = []
    @Published var title = "AEC Mirror"
    @Published var kind = "waiting"
    @Published var streaming = false
    @Published var image: UIImage?
    @Published var reachable = false
    @Published var lastUpdate: Date?
    private var lastTextTimestamp = 0.0
    private var lastImageTimestamp = 0.0
    private var session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    override init() {
        super.init(); session?.delegate = self; session?.activate()
    }
    func refresh() {
        guard let session = session, session.activationState == .activated else { return }
        reachable = session.isReachable
        receive(session.receivedApplicationContext)
        if reachable { session.sendMessage(["command": "refresh"], replyHandler: nil, errorHandler: nil) }
    }
    private func receive(_ packet: [String: Any]) {
        guard packet["version"] as? Int == 1, let nextKind = packet["kind"] as? String,
              let timestamp = packet["sentAt"] as? Double else { return }
        if nextKind == "page" {
            guard timestamp >= lastImageTimestamp, timestamp >= lastTextTimestamp,
                  (kind == "live" || kind == "paused"), let jpeg = packet["image"] as? Data, jpeg.count <= 42000 else { return }
            lastImageTimestamp = timestamp; image = UIImage(data: jpeg)
            return
        }
        guard timestamp > lastTextTimestamp else { return }
        lastTextTimestamp = timestamp
        let changedPage = title != (packet["title"] as? String ?? "ChatGPT")
        kind = nextKind; title = packet["title"] as? String ?? "ChatGPT"
        streaming = packet["streaming"] as? Bool ?? false
        messages = (packet["messages"] as? [[String: String]] ?? []).enumerated().map {
            MirrorTurn(id: "\($0.offset)-\($0.element["id"] ?? "turn")", role: $0.element["role"] ?? "assistant", text: $0.element["text"] ?? "")
        }
        if nextKind != "paused" && (nextKind != "live" || changedPage) { image = nil }
        lastUpdate = Date(timeIntervalSince1970: timestamp)
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }
    func sessionReachabilityDidChange(_ session: WCSession) { DispatchQueue.main.async { [weak self] in self?.refresh() } }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.receive(message) }
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.receive(applicationContext) }
    }
}

struct WatchMirrorScreen: View {
    @ObservedObject var mirror: WatchMirror
    @State private var zoom = 1.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let image = mirror.image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: max(geometry.size.width, 1) * zoom)
                            .frame(minHeight: geometry.size.height)
                    }
                    .focusable()
                    .digitalCrownRotation(
                        $zoom,
                        from: 1.0,
                        through: 3.0,
                        by: 0.25,
                        sensitivity: .low,
                        isContinuous: false,
                        isHapticFeedbackEnabled: true
                    )
                    .accessibilityLabel("مرآة مباشرة لشاشة الآيفون")
                    .onTapGesture { mirror.refresh() }
                } else {
                    VStack(spacing: 8) {
                        if mirror.kind == "live" {
                            ProgressView()
                            Text("جاري نقل الشاشة…").font(.caption)
                        } else {
                            Image(systemName: mirror.kind == "cleared" ? "pause.circle" : "iphone.and.arrow.forward")
                                .font(.title2)
                                .foregroundColor(.mint)
                            Text(mirror.title).font(.caption).multilineTextAlignment(.center)
                            Text("افتح AEC Mirror على الآيفون لإظهار الشاشة هنا.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button { mirror.refresh() } label: {
                                Image(systemName: "arrow.clockwise")
                            }.accessibilityLabel("تحديث من الآيفون")
                        }
                    }
                    .padding()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}
