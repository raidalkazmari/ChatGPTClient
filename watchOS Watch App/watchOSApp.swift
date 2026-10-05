import SwiftUI
import WatchConnectivity
import WatchKit

@main
struct watchOS_Watch_App: App {
    @StateObject private var mirror = WatchMirror()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup { WatchMirrorScreen(mirror: mirror).onChange(of: phase) { if $0 == .active { mirror.refresh() } } }
    }
}
struct MirrorBlock: Codable {
    var type: String
    var text: String
    var marker: String?
    var depth: Int?
    var rows: [[String]]?
    var imageID: String?
    var unavailable: Bool?
}
struct MirrorTurn: Codable, Identifiable {
    var id: String
    var role: String
    var blocks: [MirrorBlock]
}
struct SavedConversation: Codable {
    var conversation: String
    var messages: [MirrorTurn]
    var timestamp: Double
    var truncated: Bool
}
final class WatchMirror: NSObject, ObservableObject, WCSessionDelegate {
    @Published var messages: [MirrorTurn] = []
    @Published var truncated = false
    @Published var images: [String: UIImage] = [:]
    @Published var streaming = false
    @Published var refreshPending = false
    private var timestamp = 0.0
    private var conversation = ""
    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AECGPT")
    override init() {
        super.init()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: directory.appendingPathComponent("conversation.json")),
           let saved = try? JSONDecoder().decode(SavedConversation.self, from: data) {
            messages = saved.messages; timestamp = saved.timestamp; conversation = saved.conversation; truncated = saved.truncated
            loadImages()
        }
        session?.delegate = self; session?.activate()
    }
    func refresh() {
        guard let session = session, session.activationState == .activated else { return }
        receive(session.receivedApplicationContext)
        guard session.isReachable, !refreshPending else { return }
        refreshPending = true
        session.sendMessage(["command": "refresh"], replyHandler: nil) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshPending = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.refreshPending = false }
    }
    private func receive(_ packet: [String: Any]) {
        guard packet["version"] as? Int == 2, let kind = packet["kind"] as? String,
              let sent = packet["sentAt"] as? Double, sent > timestamp else { return }
        guard kind == "live" || kind == "cleared" else { return }
        timestamp = sent; refreshPending = false
        if kind == "cleared" {
            messages = []; images = [:]; streaming = false; truncated = false
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return
        }
        guard let raw = packet["messages"], let data = try? JSONSerialization.data(withJSONObject: raw),
              let turns = try? JSONDecoder().decode([MirrorTurn].self, from: data) else { return }
        messages = turns; conversation = packet["conversation"] as? String ?? ""
        streaming = packet["streaming"] as? Bool ?? false; truncated = packet["truncated"] as? Bool ?? false
        let saved = SavedConversation(conversation: conversation, messages: messages, timestamp: timestamp, truncated: truncated)
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: directory.appendingPathComponent("conversation.json"), options: .atomic) }
        loadImages()
    }
    private func loadImages() {
        let wanted = Set(messages.flatMap { $0.blocks.compactMap(\.imageID) })
        images = images.filter { wanted.contains($0.key) }
        for id in wanted where validID(id) && images[id] == nil {
            if let data = try? Data(contentsOf: directory.appendingPathComponent(id + ".jpg")), let image = UIImage(data: data) { images[id] = image }
        }
        // Bound disk usage without deleting images awaiting their matching manifest.
        if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]), files.count > 80 {
            for file in files where file.pathExtension == "jpg" && !wanted.contains(file.deletingPathExtension().lastPathComponent) { try? FileManager.default.removeItem(at: file) }
        }
    }
    private func validID(_ id: String) -> Bool { id.range(of: "^img-[a-f0-9]{1,8}$", options: .regularExpression) != nil }
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let id = file.metadata?["imageID"] as? String, validID(id),
              let data = try? Data(contentsOf: file.fileURL), data.count < 210000, let image = UIImage(data: data) else { return }
        // Copy before this delegate returns; WatchConnectivity removes its temporary file.
        try? data.write(to: directory.appendingPathComponent(id + ".jpg"), options: .atomic)
        DispatchQueue.main.async { [weak self] in self?.images[id] = image }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { DispatchQueue.main.async { [weak self] in self?.refresh() } }
    func sessionReachabilityDidChange(_ session: WCSession) { DispatchQueue.main.async { [weak self] in self?.refresh() } }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { DispatchQueue.main.async { [weak self] in self?.receive(message) } }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { DispatchQueue.main.async { [weak self] in self?.receive(applicationContext) } }
}
struct WatchMirrorScreen: View {
    @ObservedObject var mirror: WatchMirror
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { mirror.refresh() } label: { Image(systemName: mirror.refreshPending ? "ellipsis" : "arrow.clockwise").font(.system(size: 13, weight: .semibold)).foregroundColor(.mint).frame(width: 28, height: 22) }
                    .buttonStyle(.plain).accessibilityLabel("تحديث المحادثة")
                Spacer(minLength: 0)
            }.frame(height: 22)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if mirror.messages.isEmpty { Text("AECGPT\nلا توجد محادثة محفوظة بعد").font(.caption).foregroundColor(.secondary).padding(.top, 24) }
                    ForEach(mirror.messages) { turn in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(turn.role == "user" ? "أنت" : "ChatGPT").font(.system(size: 10, weight: .semibold)).foregroundColor(turn.role == "user" ? .mint : .secondary)
                            ForEach(Array(turn.blocks.enumerated()), id: \.offset) { _, block in
                                RichBlockView(block: block, image: block.imageID.flatMap { mirror.images[$0] })
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if mirror.truncated { Text("المحادثة طويلة؛ جزء منها غير منقول. راجع الآيفون لبقية المحتوى.").font(.caption2).foregroundColor(.orange) }
                    if mirror.streaming { Text("يكتب الآن…").font(.caption2).foregroundColor(.mint) }
                }.padding(.horizontal, 4).padding(.bottom, 8)
            }
        }.background(Color.black).ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("aecgpt-rich-chat-build-4")
    }
}
struct RichBlockView: View {
    let block: MirrorBlock
    let image: UIImage?
    @State private var expanded = false
    private func formatted(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
    var body: some View {
        Group {
            switch block.type {
            case "image":
                if let image = image {
                    Button { expanded = true } label: { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(block.text) }.buttonStyle(.plain)
                        .sheet(isPresented: $expanded) { ZoomImage(image: image) }
                } else {
                    Label(block.unavailable == true ? "صورة محمية: راجع الآيفون" : "الصورة قيد النقل؛ أبقِ الجهازين قريبين", systemImage: "photo").font(.caption2).foregroundColor(.secondary)
                }
            case "heading": Text(formatted(block.text)).font(.system(size: 16, weight: .bold))
            case "list":
                HStack(alignment: .top, spacing: 5) {
                    Text(block.marker ?? "•").font(.system(size: 14, weight: .semibold)).fixedSize()
                    Text(formatted(block.text)).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.leading, CGFloat(min(block.depth ?? 0, 4)) * 7)
            case "table":
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array((block.rows ?? []).enumerated()), id: \.offset) { index, row in
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                    Text(formatted(cell)).font(.system(size: 12, weight: index == 0 ? .bold : .regular)).frame(width: 100, alignment: .leading).padding(6)
                                }
                            }.background(index == 0 ? Color.white.opacity(0.14) : Color.white.opacity(0.04))
                            Divider()
                        }
                    }
                }
            case "code", "formula":
                ScrollView(.horizontal) { Text(block.text).font(.system(size: 12, design: .monospaced)).padding(6) }.background(Color.white.opacity(0.06))
            case "quote": Text(formatted(block.text)).italic().padding(.leading, 6).overlay(alignment: .leading) { Rectangle().fill(Color.mint).frame(width: 2) }
            default: Text(formatted(block.text))
            }
        }.font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
    }
}
struct ZoomImage: View {
    let image: UIImage
    @State private var zoom = 1.0
    var body: some View {
        VStack {
            ScrollView([.horizontal, .vertical]) { Image(uiImage: image).resizable().scaledToFit().frame(width: WKInterfaceDevice.current().screenBounds.width * zoom) }
            HStack { Button("−") { zoom = max(1, zoom - 0.5) }; Text("\(Int(zoom * 100))%").font(.caption2); Button("+") { zoom = min(4, zoom + 0.5) } }
        }
    }
}
