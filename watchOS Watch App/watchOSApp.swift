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
    @Published var reachable = false
    @Published var lastUpdate: Date?
    private var lastTextTimestamp = 0.0
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
        guard nextKind != "paused" else { return }
        guard timestamp > lastTextTimestamp else { return }
        lastTextTimestamp = timestamp
        let changedPage = title != (packet["title"] as? String ?? "ChatGPT")
        kind = nextKind; title = packet["title"] as? String ?? "ChatGPT"
        streaming = packet["streaming"] as? Bool ?? false
        messages = (packet["messages"] as? [[String: String]] ?? []).enumerated().map {
            MirrorTurn(id: "\($0.offset)-\($0.element["id"] ?? "turn")", role: $0.element["role"] ?? "assistant", text: $0.element["text"] ?? "")
        }
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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { mirror.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.mint)
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("تحديث المحادثة")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 5)
            .frame(height: 23)

            if mirror.messages.isEmpty {
                Spacer(minLength: 0)
                Text("لا توجد محادثة محفوظة")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(mirror.messages) { turn in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(turn.role == "user" ? "أنت" : "ChatGPT")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(turn.role == "user" ? .mint : .secondary)
                                    Text(turn.text)
                                        .font(.system(size: 14))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 5)
                                .id(turn.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: mirror.lastUpdate) { _ in
                        if let latest = mirror.messages.last { proxy.scrollTo(latest.id, anchor: .bottom) }
                    }
                    .onAppear {
                        if let latest = mirror.messages.last { proxy.scrollTo(latest.id, anchor: .bottom) }
                    }
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
    }
}
