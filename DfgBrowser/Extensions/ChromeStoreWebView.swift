import SwiftUI
import WebKit

struct ChromeStoreWebView: UIViewRepresentable {
    @EnvironmentObject var extensionManager: ExtensionManager
    let startURL = URL(string: "https://chromewebstore.google.com/category/extensions?hl=ru")!
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.websiteDataStore = .default()
        
        // Spoof desktop Chrome to bypass iOS block
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        webView.load(URLRequest(url: startURL))
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(extensionManager)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        let extensionManager: ExtensionManager
        
        init(_ manager: ExtensionManager) {
            self.extensionManager = manager
        }
        
        // Intercept CRX / install clicks
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow); return
            }
            let s = url.absoluteString
            // Chrome Web Store detail pages: /detail/NAME/EXTENSION_ID
            if s.contains("chromewebstore.google.com/detail/") {
                // Let it load, we inject install button JS
                decisionHandler(.allow)
                return
            }
            // Direct CRX
            if url.pathExtension == "crx" || s.contains("clients2.google.com/service/update2/crx") {
                decisionHandler(.download)
                return
            }
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let mime = navigationResponse.response.mimeType,
               mime == "application/x-chrome-extension" ||
               navigationResponse.response.url?.pathExtension == "crx" {
                decisionHandler(.download)
                return
            }
            // Also catch CRX via URL pattern
            if let url = navigationResponse.response.url,
               url.absoluteString.contains("update2/crx") {
                decisionHandler(.download)
                return
            }
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Inject "Установить в Dfg" button on extension detail pages
            let js = """
(function(){
  if(location.href.includes('/detail/')){
    if(document.getElementById('dfg-install')) return;
    const m = location.pathname.match(/\\/detail\\/[^\"]+\\/([a-p]{32})/);
    if(!m) return;
    const extId = m[1];
    const btn = document.createElement('button');
    btn.id='dfg-install';
    btn.textContent='⬇ УСТАНОВИТЬ В DFG BROWSER';
    btn.style.cssText='position:fixed;bottom:20px;right:20px;z-index:999999;background:#000;color:#fff;padding:14px 20px;border:none;border-radius:10px;font-weight:800;font-family:monospace;box-shadow:0 8px 24px rgba(0,0,0,.3);cursor:pointer;';
    btn.onclick=function(){
      location.href='dfg-install://'+extId;
    };
    document.body.appendChild(btn);
  }
})();
true;
"""
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
        
        // Handle custom dfg-install:// scheme
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            if let url = navigationAction.request.url, url.scheme == "dfg-install" {
                let extId = url.host ?? ""
                Task {
                    do {
                        try await extensionManager.installFromStore(storeId: extId, name: extId)
                    } catch {
                        print("Install failed: \\(error)")
                    }
                }
                // Show alert via JS
                webView.evaluateJavaScript("alert('Установка '+\"\(url.host ?? "")\"+' началась. Проверь вкладку Расширения.')", completionHandler: nil)
                decisionHandler(.cancel, preferences)
                return
            }
            decisionHandler(.allow, preferences)
        }
        
        // WKDownloadDelegate
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]
        
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFilename)
            try? FileManager.default.removeItem(at: temp)
            downloadDestinations[ObjectIdentifier(download)] = temp
            completionHandler(temp)
        }
        
        func downloadDidFinish(_ download: WKDownload) {
            let id = ObjectIdentifier(download)
            guard let fileURL = downloadDestinations[id] else { return }
            downloadDestinations.removeValue(forKey: id)
            Task {
                guard let data = try? Data(contentsOf: fileURL) else { return }
                var storeId = "unknown"
                if let u = download.originalRequest?.url?.absoluteString,
                   let range = u.range(of: "[a-z]{32}", options: .regularExpression) {
                    storeId = String(u[range])
                }
                try? await extensionManager.installCRX(data: data, storeId: storeId, fallbackName: storeId)
            }
        }
        
        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            print("Download failed: \\(error)")
        }
        
        // new window
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}

// Wrapper sheet with real store + installed list tabs
struct ChromeStoreViewV2: View {
    @EnvironmentObject var extensionManager: ExtensionManager
    @Environment(\.dismiss) var dismiss
    @State private var tab = 0 // 0 store, 1 installed
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Chrome Web Store").tag(0)
                    Text("Установленные (\(extensionManager.installedExtensions.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .tint(.black)
                
                if tab == 0 {
                    ChromeStoreWebView()
                        .environmentObject(extensionManager)
                        .edgesIgnoringSafeArea(.bottom)
                } else {
                    InstalledExtensionsListView()
                        .environmentObject(extensionManager)
                }
            }
            .navigationTitle("Расширения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("DFG").font(.system(size: 14, weight: .black, design: .monospaced))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundColor(.black)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                }
            }
        }
        .accentColor(.black)
    }
}

struct InstalledExtensionsListView: View {
    @EnvironmentObject var extensionManager: ExtensionManager
    
    var body: some View {
        List {
            ForEach(extensionManager.installedExtensions) { ext in
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black, lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                        .overlay(Text(String(ext.name.prefix(1))).font(.system(size: 16, weight: .black, design: .monospaced)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ext.name).font(.system(size: 15, weight: .semibold))
                        Text(ext.description).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(2)
                        Text("\(ext.id) • v\(ext.version)").font(.system(size: 9, design: .monospaced)).foregroundColor(.gray)
                        Text(ext.permissions.joined(separator: ", ")).font(.system(size: 9, design: .monospaced)).foregroundColor(.black.opacity(0.5)).lineLimit(1)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { ext.enabled },
                        set: { _ in extensionManager.toggle(ext) }
                    )).labelsHidden()
                    .tint(.black)
                }
                .padding(.vertical, 4)
                .swipeActions {
                    Button(role: .destructive) { extensionManager.remove(ext) } label: { Label("Удалить", systemImage: "trash") }
                }
                .listRowBackground(Color.white)
            }
        }
        .listStyle(.plain)
        .background(Color(red: 0.97, green: 0.97, blue: 0.97))
    }
}
