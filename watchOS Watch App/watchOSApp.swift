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
                  kind == "live", let jpeg = packet["image"] as? Data, jpeg.count <= 42000 else { return }
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
        if nextKind != "live" || changedPage { image = nil }
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
    @State private var pageMode = false
    @State private var followLatest = true
    @State private var zoom = 1.0
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Circle().fill(mirror.reachable ? Color.mint : .orange).frame(width: 5, height: 5)
                Text(mirror.kind == "live" ? (mirror.streaming ? "يكتب الآن…" : "من الآيفون") : "AEC Mirror")
                    .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                Spacer()
                Button { mirror.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).accessibilityLabel("تحديث من الآيفون")
            }
            HStack(spacing: 6) {
                Button { pageMode = false } label: { Text("نص").frame(maxWidth: .infinity) }
                    .tint(pageMode ? .gray : .mint)
                Button { pageMode = true } label: { Text("صفحة").frame(maxWidth: .infinity) }
                    .tint(pageMode ? .mint : .gray)
            }.font(.caption).buttonStyle(.bordered)
            if mirror.kind != "live" {
                ScrollView {
                    VStack(spacing: 12) {
                        Image(systemName: mirror.kind == "cleared" ? "pause.circle" : "iphone.and.arrow.forward").font(.largeTitle).foregroundColor(.mint)
                        Text(mirror.title).font(.headline).multilineTextAlignment(.center)
                        Text(mirror.kind == "waiting" ? "افتح متصفح AEC Mirror على الجوال. دخولك هناك فقط، ثم يظهر الرد هنا." : "افتح المتصفح على الجوال لمتابعة العرض.")
                            .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                    }.padding(.top, 12)
                }
            } else if pageMode {
                if let image = mirror.image {
                    GeometryReader { geometry in
                        ScrollView([.horizontal, .vertical]) {
                            Image(uiImage: image).resizable().scaledToFit().frame(width: geometry.size.width * zoom)
                        }
                    }
                    HStack {
                        Button { zoom = max(1, zoom - 0.5) } label: { Image(systemName: "minus.magnifyingglass") }
                        Text("\(Int(zoom * 100))%").font(.caption2)
                        Button { zoom = min(3, zoom + 0.5) } label: { Image(systemName: "plus.magnifyingglass") }
                    }.buttonStyle(.plain)
                } else {
                    Spacer(); ProgressView("بانتظار صورة الصفحة…").font(.caption); Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if mirror.messages.isEmpty {
                                Text("افتح محادثة أو أرسل سؤالك من الجوال. إذا لم يظهر النص جرّب عرض «صفحة».").font(.caption).foregroundColor(.secondary)
                            }
                            ForEach(mirror.messages) { turn in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(turn.role == "user" ? "أنت" : "ChatGPT").font(.caption2.bold()).foregroundColor(turn.role == "user" ? .mint : .secondary)
                                    Text(turn.text).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
                                }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(turn.role == "user" ? Color.mint.opacity(0.10) : Color.white.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            Color.clear.frame(height: 1).id("latest")
                        }
                    }
                    .onChange(of: mirror.lastUpdate) { _ in if followLatest { proxy.scrollTo("latest", anchor: .bottom) } }
                    .onAppear { if followLatest { proxy.scrollTo("latest", anchor: .bottom) } }
                }
                Button { followLatest.toggle() } label: {
                    Label(followLatest ? "متابعة الرد" : "قراءة السابق", systemImage: followLatest ? "arrow.down.to.line" : "book").font(.caption2)
                }.buttonStyle(.plain).foregroundColor(.mint)
            }
        }.padding(.horizontal, 4)
    }
}
