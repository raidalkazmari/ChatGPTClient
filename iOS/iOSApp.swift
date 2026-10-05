import SwiftUI
import WebKit
import WatchConnectivity
import UIKit

@main
struct iOSApp: App {
    @StateObject private var browser = MirrorBrowser()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            BrowserScreen(browser: browser)
                .onChange(of: phase) { browser.setActive($0 == .active) }
        }
    }
}

struct BrowserScreen: View {
    @ObservedObject var browser: MirrorBrowser
    @State private var showHelp = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "applewatch.radiowaves.left.and.right").foregroundColor(.mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("AEC · Mirror").font(.headline)
                    Text(browser.status).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button { browser.toggleSync() } label: {
                    Image(systemName: browser.syncEnabled ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2).foregroundColor(.mint)
                }.accessibilityLabel(browser.syncEnabled ? "إيقاف ومسح الساعة" : "تشغيل المزامنة")
                Button { showHelp = true } label: { Image(systemName: "info.circle") }
            }.padding(14).background(Color(.secondarySystemBackground))
            if browser.loading { ProgressView().progressViewStyle(.linear).tint(.mint) }
            BrowserWebView(webView: browser.webView)
            if let error = browser.error {
                Text(error).font(.caption).foregroundColor(.orange).padding(8)
            }
            HStack {
                Button { browser.webView.goBack() } label: { Image(systemName: "chevron.backward") }.disabled(!browser.canGoBack)
                Spacer()
                Button { browser.webView.goForward() } label: { Image(systemName: "chevron.forward") }.disabled(!browser.canGoForward)
                Spacer()
                Text(browser.host).font(.caption).lineLimit(1)
                Spacer()
                Button { browser.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                Spacer()
                Button { browser.home() } label: { Image(systemName: "house") }
            }.padding(16).background(Color(.secondarySystemBackground))
        }.preferredColorScheme(.dark)
        .sheet(isPresented: $showHelp) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Label("حسابك في الجوال، الرد في ساعتك", systemImage: "applewatch").font(.title2.bold())
                        Text("سجّل دخولك إلى chatgpt.com داخل هذا المتصفح. افتح AEC Mirror في الساعة، ثم أرسل سؤالك أو صورتك من الجوال.")
                        Text("في الساعة اختر «نص» لقراءة المحادثة، أو «صفحة» لمشاهدة صورة الصفحة. قفل الجوال أو الخروج من المتصفح يوقف التحديث الحي.")
                        Text("جلسة الموقع تبقى على الجوال فقط. الساعة لا تستقبل كلمة المرور أو ملفات تعريف الارتباط. زر الإيقاف يمسح العرض المنقول، ولا يخرجك من ChatGPT.")
                        Text("دخول Google قد لا يعمل داخل المتصفح المدمج. هذا نموذج تجريبي؛ تسجيل الدخول ورفع الصور يحتاجان تجربة على جهاز حقيقي. تغيير صفحة ChatGPT قد يؤثر في استخراج النصوص. عرض الصفحة لا يعتمد على شكل الرسائل.")
                        Text("ليس تطبيقًا رسميًا من OpenAI. لا يستخدم مفتاح API. حدود حسابك في الموقع تبقى كما هي.").foregroundColor(.secondary)
                    }.padding(24)
                }.navigationTitle("طريقة الاستخدام").toolbar { Button("تم") { showHelp = false } }
            }
        }
    }
}

struct BrowserWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var owner: MirrorBrowser?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.acceptScript(message)
    }
}

final class MirrorBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WCSessionDelegate {
    @Published var status = "افتح التطبيق على الساعة"
    @Published var syncEnabled = true
    @Published var loading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var host = "chatgpt.com"
    @Published var error: String?
    let webView: WKWebView
    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private var active = true
    private var timer: Timer?
    private var snapshotInFlight = false
    private var generation = 0
    private var revision = 0
    private var lastText: [String: Any] = [:]
    private var safePage = false
    private var lastFingerprint = ""
    private var lastJPEG: Data?
    private var lastImageSent = Date.distantPast

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let proxy = WeakScriptHandler()
        config.userContentController.add(proxy, name: "aecMirror")
        config.userContentController.addUserScript(WKUserScript(source: Self.extractor, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        proxy.owner = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        session?.delegate = self
        session?.activate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.capturePage() }
        home()
    }
    deinit { timer?.invalidate() }
    func home() { webView.load(URLRequest(url: URL(string: "https://chatgpt.com/")!)) }
    func setActive(_ value: Bool) {
        active = value
        if !value { generation += 1; publishState(kind: "paused", title: "الجوال مقفل أو المتصفح بالخلفية") }
        else if syncEnabled { refresh() }
    }
    func toggleSync() {
        syncEnabled.toggle()
        generation += 1
        if syncEnabled { refresh() }
        else { lastText = [:]; lastJPEG = nil; publishState(kind: "cleared", title: "المزامنة متوقفة") }
    }
    func refresh() {
        guard active, syncEnabled else { return }
        webView.evaluateJavaScript("window.__aecEmit && window.__aecEmit(true)")
        lastJPEG = nil
        capturePage()
    }
    private func updateStatus() {
        guard syncEnabled else { status = "المزامنة متوقفة"; return }
        guard active else { status = "التحديث متوقف بالخلفية"; return }
        guard let session = session else { status = "اتصال الساعة غير متاح"; return }
        if !session.isPaired { status = "اربط ساعة بالآيفون" }
        else if !session.isWatchAppInstalled { status = "ثبّت تطبيق الساعة أولًا" }
        else if session.isReachable { status = "متصل · مزامنة مباشرة" }
        else { status = "افتح التطبيق في الساعة" }
    }
    private func publishState(kind: String, title: String) {
        lastText = ["kind": kind, "title": title, "messages": [[String: String]]()]
        transmit(lastText, context: true)
    }
    private func transmit(_ content: [String: Any], context: Bool) {
        guard let session = session, session.activationState == .activated else { return }
        revision += 1
        var packet = content
        packet["version"] = 1
        packet["revision"] = revision
        packet["sentAt"] = Date().timeIntervalSince1970
        if context {
            do { try session.updateApplicationContext(packet) }
            catch { self.error = "تعذّر حفظ تحديث الساعة: \(error.localizedDescription)" }
        }
        if session.isReachable {
            session.sendMessage(packet, replyHandler: nil) { [weak self] _ in
                DispatchQueue.main.async { self?.status = "تعذّر الإرسال؛ افتح تطبيق الساعة" }
            }
        }
        updateStatus()
    }
    func acceptScript(_ message: WKScriptMessage) {
        guard active, syncEnabled, message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.host == "chatgpt.com",
              let body = message.body as? [String: Any] else { return }
        safePage = body["safe"] as? Bool == true
        guard safePage else { generation += 1; publishState(kind: "signin", title: "أكمل تسجيل الدخول على الآيفون"); return }
        let raw = body["messages"] as? [[String: Any]] ?? []
        var budget = 24000
        var messages = [[String: String]]()
        for item in raw.reversed() {
            guard budget > 0, let text = item["text"] as? String else { continue }
            var characters = [Character]()
            for character in text.reversed() {
                let size = String(character).utf8.count
                if size > budget { break }
                characters.append(character)
                budget -= size
            }
            let bounded = String(characters.reversed())
            if !bounded.isEmpty {
                messages.insert(["id": String((item["id"] as? String ?? UUID().uuidString).prefix(128)),
                                 "role": item["role"] as? String == "user" ? "user" : "assistant", "text": bounded], at: 0)
            }
        }
        let next: [String: Any] = ["kind": "live", "title": String((body["title"] as? String ?? "ChatGPT").prefix(180)),
                                  "messages": messages, "streaming": body["streaming"] as? Bool ?? false]
        lastText = next
        // Sorted JSON produces a stable signature, independent of dictionary order.
        let fingerprint = (try? JSONSerialization.data(withJSONObject: next, options: .sortedKeys))?.base64EncodedString() ?? ""
        if fingerprint != lastFingerprint { lastFingerprint = fingerprint; transmit(next, context: true) }
        else { transmit(next, context: false) } // forced refresh/reconnect needs the current state
    }
    private func capturePage() {
        updateStatus()
        guard active, syncEnabled, safePage, !loading, !snapshotInFlight,
              webView.url?.host == "chatgpt.com", session?.isReachable == true,
              webView.bounds.width > 0 else { return }
        snapshotInFlight = true
        let expectedGeneration = generation
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        config.snapshotWidth = NSNumber(value: 280)
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            guard let self = self else { return }
            self.snapshotInFlight = false
            guard self.active, self.syncEnabled, self.safePage, expectedGeneration == self.generation,
                  let image = image else { return }
            var jpeg = image.jpegData(compressionQuality: 0.55)
            if (jpeg?.count ?? 0) > 42000 { jpeg = image.jpegData(compressionQuality: 0.2) }
            guard let data = jpeg, data.count <= 42000 else { return }
            if data == self.lastJPEG && Date().timeIntervalSince(self.lastImageSent) < 8 { return }
            self.lastJPEG = data
            self.lastImageSent = Date()
            self.transmit(["kind": "page", "image": data], context: false)
        }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true; error = nil; safePage = false; generation += 1; lastJPEG = nil
        if active, syncEnabled { publishState(kind: "loading", title: "فتح الصفحة على الآيفون…") }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false; host = webView.url?.host ?? "chatgpt.com"
        canGoBack = webView.canGoBack; canGoForward = webView.canGoForward
        if host != "chatgpt.com", syncEnabled { publishState(kind: "signin", title: "أكمل تسجيل الدخول على الآيفون") }
        refresh()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loading = false
        if (error as NSError).code != NSURLErrorCancelled { self.error = error.localizedDescription }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loading = false; self.error = error.localizedDescription
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        let host = url.host ?? ""
        let approved = host == "chatgpt.com" || host == "openai.com" || host.hasSuffix(".openai.com") || host == "accounts.google.com" || host == "appleid.apple.com"
        if url.scheme == "https" && approved { decisionHandler(.allow) }
        else if action.navigationType == .linkActivated && url.scheme == "https" {
            UIApplication.shared.open(url); decisionHandler(.cancel)
        } else { decisionHandler(.cancel) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil { webView.load(action.request) }
        return nil
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in self?.updateStatus(); self?.refresh() }
    }
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in self?.updateStatus(); self?.refresh() }
    }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["command"] as? String == "refresh" {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if !self.syncEnabled { self.publishState(kind: "cleared", title: "المزامنة متوقفة") }
                else if !self.active { self.publishState(kind: "paused", title: "افتح المتصفح على الآيفون") }
                else { self.refresh() }
            }
        }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    static let extractor = #"""
    (() => {
      if (location.hostname !== 'chatgpt.com' || window.__aecEmit) return;
      let previous = '', queued = false;
      window.__aecEmit = (force = false) => {
        const safe = !/\/(auth|login|signup)(\/|$)/.test(location.pathname) &&
          !document.querySelector('input[type="password"], input[type="email"]');
        const nodes = [...document.querySelectorAll('[data-message-author-role]')];
        let remaining = 22000;
        const messages = nodes.slice(-24).reverse().map((node, index) => {
          const role = node.getAttribute('data-message-author-role');
          if (!['user','assistant'].includes(role)) return null;
          const content = node.querySelector('.markdown, .whitespace-pre-wrap') || node;
          let text = (content.innerText || '').trim();
          if (!text && node.querySelector('img')) text = '📷 صورة';
          text = remaining > 0 ? text.slice(-remaining) : ''; remaining -= text.length;
          return {id: node.getAttribute('data-message-id') || `turn-${nodes.length-index}`, role, text};
        }).filter(item => item && item.text).reverse();
        const payload = {safe, title: document.title || 'ChatGPT', messages: safe ? messages : [],
          streaming: !!document.querySelector('[data-testid="stop-button"], button[aria-label="Stop generating"]')};
        const signature = JSON.stringify(payload);
        if (force || signature !== previous) {
          previous = signature;
          window.webkit.messageHandlers.aecMirror.postMessage(payload);
        }
      };
      new MutationObserver(() => {
        if (queued) return; queued = true;
        setTimeout(() => { queued = false; window.__aecEmit(); }, 300);
      }).observe(document.documentElement, {childList: true, subtree: true, characterData: true});
      setInterval(() => window.__aecEmit(), 1000);
      window.__aecEmit(true);
    })();
    """#
}
