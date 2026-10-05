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
                Image("BrandLogo").resizable().scaledToFit().frame(width: 72, height: 38).accessibilityLabel("AECGPT ABOFAHAD")
                VStack(alignment: .leading, spacing: 3) {
                    Text("AECGPT Backup").font(.headline)
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
            BrowserWebView(webView: browser.displayWebView).id(browser.popupVisible)
            if browser.popupVisible { Button("إغلاق نافذة تسجيل الدخول") { browser.closePopup() }.padding(6) }
            if let error = browser.error {
                Text(error).font(.caption).foregroundColor(.orange).padding(8)
            }
            HStack {
                Button { browser.displayWebView.goBack() } label: { Image(systemName: "chevron.backward") }.disabled(!browser.canGoBack)
                Spacer()
                Button { browser.displayWebView.goForward() } label: { Image(systemName: "chevron.forward") }.disabled(!browser.canGoForward)
                Spacer()
                Text(browser.host).font(.caption).lineLimit(1)
                Spacer()
                Button { browser.displayWebView.reload() } label: { Image(systemName: "arrow.clockwise") }
                Spacer()
                Button { browser.home() } label: { Image(systemName: "house") }
            }.padding(16).background(Color(.secondarySystemBackground))
        }.preferredColorScheme(.dark)
        .sheet(isPresented: $showHelp) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Label("حسابك في الجوال، الرد في ساعتك", systemImage: "applewatch").font(.title2.bold())
                        Text("سجّل دخولك إلى chatgpt.com داخل هذا المتصفح. افتح AECGPT في الساعة، ثم أرسل سؤالك أو صورتك من الجوال.")
                        Text("تظهر العناوين وترقيم الإجابات والجداول والصور القابلة للنقل على الساعة. اسحب للقراءة، واضغط الصورة لتكبيرها. لا تقفز الصفحة عند وصول تحديث. تبقى آخر محادثة محفوظة عند إغلاق التطبيق، وتصل الردود الجديدة عند عودتك إليه.")
                        Text("جلسة الموقع تبقى على الجوال فقط. الساعة لا تستقبل كلمة المرور أو ملفات تعريف الارتباط. زر الإيقاف يمسح العرض المنقول، ولا يخرجك من ChatGPT.")
                        Text("إذا تعثر دخول Google، استخدم طريقة دخول أخرى متاحة لحسابك في صفحة ChatGPT. تسجيل الدخول في Safari لا ينقل الجلسة تلقائيًا لهذا التطبيق. الصور المحمية قد لا تنتقل؛ وتظهر مرفقات PDF كبطاقة باسم الملف بينما تبقى قراءة الصفحات على الآيفون. الرسوم والمعادلات المعقدة قد تحتاج مراجعة الآيفون.")
                        Text("في نافذة التصوير التي يعرضها iOS، اختر الفلاش Off من رمز البرق بدل Auto. التطبيق لا يستطيع كتم صوت غالق الكاميرا الذي يتحكم به iOS.").font(.footnote).foregroundColor(.secondary)
                        Divider()
                        Text("تم التطوير بواسطة ابو فهد").font(.headline)
                        Link("لتواصل INFO@ABOFAHAD.NET", destination: URL(string: "mailto:INFO@ABOFAHAD.NET")!)
                        Text("AECGPT Backup · 1.2 (5)").font(.caption).foregroundColor(.secondary)
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
    private var generation = 0
    private var revision = 0
    private var lastText: [String: Any] = [:]
    private var safePage = false
    private var lastFingerprint = ""
    private var sentAssets = Set<String>()
    private var refreshScheduled = false
    private var lastReload = Date.distantPast
    private var popup: WKWebView?
    @Published var popupVisible = false

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
        home()
    }
    var displayWebView: WKWebView { popup ?? webView }
    func closePopup() { popup = nil; popupVisible = false; refresh() }
    func home() { closePopup(); webView.load(URLRequest(url: URL(string: "https://chatgpt.com/")!)) }
    func setActive(_ value: Bool) {
        active = value
        if !value { generation += 1; updateStatus() }
        else if syncEnabled { refresh() }
    }
    func toggleSync() {
        syncEnabled.toggle()
        generation += 1
        if syncEnabled { refresh() }
        else { lastText = [:]; sentAssets.removeAll(); session?.outstandingFileTransfers.forEach { $0.cancel() }; publishState(kind: "cleared", title: "المزامنة متوقفة") }
    }
    func refresh() {
        guard active, syncEnabled else { return }
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self else { return }; self.refreshScheduled = false
            guard self.active, self.syncEnabled else { return }
            self.webView.evaluateJavaScript("window.__aecEmit && window.__aecEmit(true)")
        }
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
        lastFingerprint = ""
        lastText = ["kind": kind, "title": title, "messages": [[String: String]]()]
        transmit(lastText, context: true)
    }
    private func transmit(_ content: [String: Any], context: Bool) {
        guard let session = session, session.activationState == .activated else { return }
        revision += 1
        var packet = content
        packet["version"] = 2
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
        guard active, syncEnabled, message.frameInfo.isMainFrame, message.webView === webView,
              message.frameInfo.securityOrigin.host == "chatgpt.com",
              let body = message.body as? [String: Any] else { return }
        if let asset = body["asset"] as? String, let encoded = body["data"] as? String {
            guard webView.url?.host == "chatgpt.com", !asset.isEmpty,
                  asset.range(of: "^img-[a-f0-9]{1,8}$", options: .regularExpression) != nil,
                  encoded.count <= 260000, !sentAssets.contains(asset),
                  let session = session, session.activationState == .activated,
                  session.outstandingFileTransfers.count < 16,
                  let data = Data(base64Encoded: encoded), UIImage(data: data) != nil else { return }
            do {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AECGPT-images")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent(asset + ".jpg")
                try data.write(to: url, options: .atomic)
                session.transferFile(url, metadata: ["imageID": asset])
                sentAssets.insert(asset)
            } catch { self.error = "تعذّر تجهيز الصورة للساعة" }
            return
        }
        safePage = body["safe"] as? Bool == true
        guard safePage else { return }
        let messages = body["messages"] as? [[String: Any]] ?? []
        let next: [String: Any] = ["kind": "live", "title": String((body["title"] as? String ?? "ChatGPT").prefix(180)),
            "conversation": body["conversation"] as? String ?? "", "messages": messages,
            "truncated": body["truncated"] as? Bool ?? false, "streaming": body["streaming"] as? Bool ?? false]
        guard let bounded = try? JSONSerialization.data(withJSONObject: next), bounded.count < 55000 else {
            self.error = "المحادثة أكبر من حد النقل؛ افتح محادثة أقصر على الآيفون"; return
        }
        lastText = next
        // Sorted JSON produces a stable signature, independent of dictionary order.
        let fingerprint = (try? JSONSerialization.data(withJSONObject: next, options: .sortedKeys))?.base64EncodedString() ?? ""
        if fingerprint != lastFingerprint { lastFingerprint = fingerprint; transmit(next, context: true) }
        else { transmit(next, context: false) } // forced refresh/reconnect needs the current state
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true; error = nil; safePage = false; generation += 1
        // Keep the last conversation visible while navigating or signing in.
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false; host = webView.url?.host ?? "chatgpt.com"
        canGoBack = webView.canGoBack; canGoForward = webView.canGoForward
        if host != "chatgpt.com" { status = "أكمل تسجيل الدخول على الآيفون" }
        refresh()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loading = false
        let ns = error as NSError
        if ns.code != NSURLErrorCancelled && !(ns.domain == "WebKitErrorDomain" && ns.code == 102) { self.error = error.localizedDescription }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loading = false
        let ns = error as NSError
        if ns.code != NSURLErrorCancelled && !(ns.domain == "WebKitErrorDomain" && ns.code == 102) { self.error = error.localizedDescription }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard Date().timeIntervalSince(lastReload) > 20 else { error = "توقف المتصفح؛ اضغط تحديث لإعادة المحاولة"; return }
        lastReload = Date(); webView.reload()
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        // Permit HTTPS verification frames used by the site; the native bridge
        // still accepts only chatgpt.com main-frame messages.
        if action.targetFrame?.isMainFrame == false && url.scheme == "https" {
            decisionHandler(.allow); return
        }
        let host = url.host ?? ""
        if host == "accounts.google.com" {
            error = "Google قد يمنع الدخول داخل المتصفح المدمج. إذا تعثر، ارجع واختر طريقة دخول أخرى متاحة لحسابك."
        }
        let approved = host == "auth.openai.com" || host == "auth0.openai.com" || host == "chatgpt.com" || host == "openai.com" || host.hasSuffix(".openai.com") || host == "accounts.google.com" || host == "appleid.apple.com"
        if url.scheme == "https" && approved { decisionHandler(.allow) }
        else if action.navigationType == .linkActivated && url.scheme == "https" {
            UIApplication.shared.open(url); decisionHandler(.cancel)
        } else { decisionHandler(.cancel) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard action.targetFrame == nil, let url = action.request.url, url.scheme == "https",
              let host = url.host, host == "chatgpt.com" || host == "openai.com" || host.hasSuffix(".openai.com") || host == "accounts.google.com" || host == "appleid.apple.com" else { return nil }
        let child = WKWebView(frame: .zero, configuration: configuration)
        child.navigationDelegate = self; child.uiDelegate = self
        popup = child; popupVisible = true
        return child
    }
    func webViewDidClose(_ webView: WKWebView) { if webView === popup { closePopup() } }
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if error != nil, let id = fileTransfer.file.metadata?["imageID"] as? String { self?.sentAssets.remove(id) }
            try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        }
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
                else if self.active { self.refresh() }
                else if !self.lastText.isEmpty { self.transmit(self.lastText, context: false) }
            }
        }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    static let extractor = #"""
    (() => {
      if (location.hostname !== 'chatgpt.com' || window.__aecEmit) return;
      let previous = '', queued = false;
      const imageStates = new Map();
      const hash = s => { let h=2166136261; for(let i=0;i<s.length;i++) h=Math.imul(h^s.charCodeAt(i),16777619); return (h>>>0).toString(16); };
      const inline = n => {
        if(n.nodeType===3) return n.textContent || '';
        const tag=n.tagName;
        if(['BUTTON','SCRIPT','STYLE','SVG','IMG'].includes(tag)) return '';
        if(tag==='BR') return '\n';
        if(n.classList?.contains('katex')) return n.querySelector('annotation')?.textContent || n.textContent || '';
        const text=Array.from(n.childNodes||[]).map(inline).join('');
        if(tag==='STRONG'||tag==='B') return '**'+text+'**';
        if(tag==='EM'||tag==='I') return '*'+text+'*';
        if(tag==='CODE') return '`'+text.replace(/`/g,'')+'`';
        return text;
      };
      const picture = (img, id) => {
        const src=img.currentSrc||img.src||'';
        if(!src || !img.complete || !img.naturalWidth) return;
        if(imageStates.has(id)) return;
        imageStates.set(id,'pending');
        try {
          const canvas=document.createElement('canvas');
          const scale=Math.min(1,960/Math.max(img.naturalWidth,img.naturalHeight));
          canvas.width=Math.max(1,Math.round(img.naturalWidth*scale)); canvas.height=Math.max(1,Math.round(img.naturalHeight*scale));
          const ctx=canvas.getContext('2d'); ctx.fillStyle='#fff';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(img,0,0,canvas.width,canvas.height);
          let data=canvas.toDataURL('image/jpeg',0.75).split(',')[1];
          if(data.length>260000) data=canvas.toDataURL('image/jpeg',0.35).split(',')[1];
          if(data.length>260000) throw new Error('image too large');
          window.webkit.messageHandlers.aecMirror.postMessage({asset:id,data});
          imageStates.set(id,'sent');
        } catch (_) { imageStates.set(id,'unavailable'); }
      };
      const blocksFor = root => {
        const blocks=[];
        const direction=value=>{
          const s=String(value||'');let rtl=-1,ltr=-1;
          for(let i=0;i<s.length;i++){
            const c=s.charCodeAt(i);
            if(rtl<0&&((c>=0x0600&&c<=0x08ff)||(c>=0xfb50&&c<=0xfdff)||(c>=0xfe70&&c<=0xfeff)))rtl=i;
            if(ltr<0&&((c>=65&&c<=90)||(c>=97&&c<=122)))ltr=i;
          }
          return rtl>=0&&(ltr<0||rtl<ltr)?'rtl':'ltr';
        };
        const add=(type,text,extra={})=>{if(text.trim()) blocks.push({type,text:text.trim(),direction:extra.direction||direction(text),...extra});};
        const walk=(node,depth=0)=>{
          if(node.nodeType===3){add('text',node.textContent||'');return;}
          const tag=node.tagName;
          if(/(?:file|document).*attachment|attachment.*(?:file|document)/i.test(node.getAttribute('data-testid')||'')){
            const label=(node.getAttribute('aria-label')||node.innerText||node.textContent||'').trim();
            if(label)add('attachment',label,{format:/\.pdf(?:$|\s)/i.test(label)?'pdf':'file'});return;
          }
          if(['BUTTON','SCRIPT','STYLE','NAV'].includes(tag)) return;
          if(tag==='IMG'){
            const src=node.currentSrc||node.src||'';
            const id='img-'+hash(src); picture(node,id);
            blocks.push({type:'image',text:node.alt||'صورة مرفقة',imageID:id,unavailable:imageStates.get(id)==='unavailable',direction:'ltr'});return;
          }
          if(tag==='A'){
            const href=node.getAttribute('href')||'',label=(node.innerText||node.textContent||'').trim();
            const ext=(href.match(/\.([a-z0-9]{2,5})(?:[?#]|$)/i)||[])[1]?.toLowerCase();
            if(['pdf','doc','docx','ppt','pptx','xls','xlsx','txt','rtf'].includes(ext)||/attachment/i.test(node.getAttribute('data-testid')||'')){
              add('attachment',label||'ملف مرفق',{format:ext==='pdf'?'pdf':'file'});return;
            }
          }
          if(tag==='OL'||tag==='UL'){
            let number=Number(node.getAttribute('start'))||1;
            for(const li of Array.from(node.children||[]).filter(c=>c.tagName==='LI')){
              if(li.hasAttribute('value')) number=Number(li.getAttribute('value'));
              const prefix=tag==='OL'?`${number++}.`:'•';
              const text=Array.from(li.childNodes).filter(c=>!['UL','OL'].includes(c.tagName)).map(inline).join('').trim();
              add('list',text,{marker:prefix,depth:Math.min(depth,4)});
              for(const child of Array.from(li.children||[])) if(['UL','OL'].includes(child.tagName)) walk(child,depth+1);
              for(const img of li.querySelectorAll('img')) walk(img,depth);
            }return;
          }
          if(tag==='TABLE'){
            const rows=Array.from(node.querySelectorAll('tr')).map(row=>Array.from(row.querySelectorAll('th,td')).map(cell=>inline(cell).trim()));
            blocks.push({type:'table',text:'',rows});return;
          }
          if(tag==='PRE'){add('code',node.textContent||'');return;}
          if(node.classList?.contains('katex')){add('formula',node.querySelector('annotation')?.textContent||node.textContent||'');return;}
          if(/^H[1-6]$/.test(tag)){add('heading',inline(node));return;}
          if(tag==='P'||tag==='BLOCKQUOTE'){
            add(tag==='BLOCKQUOTE'?'quote':'text',inline(node));
            for(const img of node.querySelectorAll('img')) walk(img,depth);
            return;
          }
          if(tag==='SVG'){add('text',node.getAttribute('aria-label')||'رسم توضيحي: افتحه على الآيفون لعرضه كاملًا');return;}
          for(const child of Array.from(node.childNodes||[])) walk(child,depth);
        };
        walk(root);
        return blocks;
      };
      window.__aecEmit = (force=false) => {
        const safe=!/\/(auth|login|signup)(\/|$)/.test(location.pathname)&&!document.querySelector('input[type="password"],input[type="email"],input[autocomplete="one-time-code"]');
        if(!safe) return;
        if(force) imageStates.clear();
        const nodes=Array.from(document.querySelectorAll('[data-message-author-role]'));
        let remaining=38000, truncated=false;
        const messages=[];
        for(let i=nodes.length-1;i>=0;i--){
          const node=nodes[i],role=node.getAttribute('data-message-author-role');
          if(!['user','assistant'].includes(role)) continue;
          const blocks=blocksFor(node);
          if(!blocks.length) continue;
          const item={id:node.getAttribute('data-message-id')||`turn-${i}`,role,blocks};
          const size=new TextEncoder().encode(JSON.stringify(item)).length;
          if(size>remaining){
            truncated=true;
            if(messages.length===0){
              const kept=[]; for(const block of blocks){const n=new TextEncoder().encode(JSON.stringify(block)).length;if(n>remaining)break;kept.push(block);remaining-=n;}
              if(kept.length) messages.unshift({...item,blocks:kept});
            }
            break;
          }
          remaining-=size;messages.unshift(item);
          if(messages.length===24){truncated=i>0;break;}
        }
        const payload={safe:true,conversation:location.pathname,title:document.title||'ChatGPT',messages,truncated,
          streaming:!!document.querySelector('[data-testid="stop-button"],button[aria-label="Stop generating"]')};
        const signature=JSON.stringify(payload);
        if(force||signature!==previous){previous=signature;window.webkit.messageHandlers.aecMirror.postMessage(payload);}
      };
      const schedule=()=>{if(queued)return;queued=true;setTimeout(()=>{queued=false;window.__aecEmit();},800);};
      new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true,characterData:true});
      document.addEventListener('load',schedule,true);
      window.__aecEmit(true);
    })();
    """#
}
