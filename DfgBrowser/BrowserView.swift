import SwiftUI
import WebKit

struct BrowserView: UIViewRepresentable {
    @Binding var tab: BrowserTab
    @EnvironmentObject var extensionManager: ExtensionManager
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // Inject installed extensions
        let userContentController = WKUserContentController()
        
        for ext in extensionManager.enabledExtensions {
            for script in ext.contentScripts {
                let userScript = WKUserScript(
                    source: script,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: false
                )
                userContentController.addUserScript(userScript)
            }
        }
        
        // Lemur-style extension message bridge
        userContentController.add(context.coordinator, name: "dfgExtension")
        
        config.userContentController = userContentController
        
        // Desktop-like user agent to allow Chrome Web Store
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/605.1.15 DfgBrowser/1.0"
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        // Observers
        context.coordinator.setupObservers(webView: webView)
        
        if tab.url.scheme == "dfg" {
            webView.loadHTMLString(NewTabPage.html, baseURL: nil)
        } else {
            webView.load(URLRequest(url: tab.url))
        }
        
        context.coordinator.webView = webView
        
        // Notification listeners
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.goBack), name: .browserGoBack, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.goForward), name: .browserGoForward, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.reloadPage), name: .browserReload, object: nil)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.stopLoading), name: .browserStop, object: nil)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != tab.url && tab.url.scheme != "dfg" {
            uiView.load(URLRequest(url: tab.url))
        }
        
        // Re-inject extensions if list changed
        context.coordinator.updateExtensions(extensionManager.enabledExtensions, webView: uiView)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
        var parent: BrowserView
        weak var webView: WKWebView?
        private var progressObserver: NSKeyValueObservation?
        private var urlObserver: NSKeyValueObservation?
        private var titleObserver: NSKeyValueObservation?
        
        init(_ parent: BrowserView) {
            self.parent = parent
        }
        
        func setupObservers(webView: WKWebView) {
            progressObserver = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.parent.tab.isLoading = webView.estimatedProgress < 1.0
                    self.parent.tab.progress = webView.estimatedProgress
                    self.parent.tab.canGoBack = webView.canGoBack
                    self.parent.tab.canGoForward = webView.canGoForward
                }
            }
            urlObserver = webView.observe(\.url, options: .new) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    if let url = webView.url {
                        self?.parent.tab.url = url
                    }
                }
            }
            titleObserver = webView.observe(\.title, options: .new) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.parent.tab.title = webView.title ?? "Загрузка..."
                }
            }
        }
        
        // WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.tab.isLoading = false
            parent.tab.progress = 1.0
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                let s = url.absoluteString
                // dfg-install:// bridge from Chrome Store page
                if url.scheme == "dfg-install", let extId = url.host {
                    Task {
                        do {
                            try await ExtensionManager.shared.installFromStore(storeId: extId, name: extId)
                        } catch {
                            print("install error", error)
                        }
                    }
                    decisionHandler(.cancel)
                    return
                }
                // CRX direct
                if url.pathExtension == "crx" || s.contains("clients2.google.com/service/update2/crx") {
                    decisionHandler(.download)
                    return
                }
            }
            decisionHandler(.allow)
        }
        
        // Download CRX handling (iOS 14.5+)
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let mime = navigationResponse.response.mimeType,
               mime == "application/x-chrome-extension" {
                decisionHandler(.download)
                return
            }
            if let url = navigationResponse.response.url,
               url.pathExtension == "crx" || url.absoluteString.contains("update2/crx") {
                decisionHandler(.download)
                return
            }
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }
        
        // Bridge
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // Extension messaging
        }
        
        @objc func goBack() { webView?.goBack() }
        @objc func goForward() { webView?.goForward() }
        @objc func reloadPage() { webView?.reload() }
        @objc func stopLoading() { webView?.stopLoading() }
        
        func updateExtensions(_ extensions: [InstalledExtension], webView: WKWebView) {
            // Hot-reload content scripts if needed
        }
        
        // For _blank targets
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
        
        // MARK: - WKDownloadDelegate
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFilename)
            try? FileManager.default.removeItem(at: tmp)
            downloadDestinations[ObjectIdentifier(download)] = tmp
            completionHandler(tmp)
        }
        
        func downloadDidFinish(_ download: WKDownload) {
            let id = ObjectIdentifier(download)
            guard let fileURL = downloadDestinations[id] else { return }
            downloadDestinations.removeValue(forKey: id)
            Task {
                guard let data = try? Data(contentsOf: fileURL) else { return }
                var storeId = "downloaded-ext"
                if let original = download.originalRequest?.url?.absoluteString,
                   let range = original.range(of: "[a-z]{32}", options: .regularExpression) {
                    storeId = String(original[range])
                }
                try? await ExtensionManager.shared.installCRX(data: data, storeId: storeId, fallbackName: storeId)
            }
        }
        
        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            print("CRX download failed:", error)
        }
    }
}

enum NewTabPage {
    static let html = """
<!DOCTYPE html>
<html lang="ru">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
*{margin:0;padding:0;box-sizing:border-box;font-family: 'SF Mono', 'Menlo', monospace;}
body{background:#fff;color:#000;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;}
.logo{font-size:48px;font-weight:800;letter-spacing:-1px;margin-bottom:8px;}
.sub{font-size:13px;color:#666;letter-spacing:2px;text-transform:uppercase;margin-bottom:40px;}
.grid{display:grid;grid-template-columns:repeat(4,72px);gap:22px;margin-bottom:40px;}
.tile{width:72px;height:72px;border:1.5px solid #000;display:flex;align-items:center;justify-content:center;font-size:22px;text-decoration:none;color:#000;background:#fff;transition:all .15s;}
.tile:hover{background:#000;color:#fff;}
.label{font-size:10px;text-align:center;margin-top:6px;color:#444;}
.wrap{text-align:center;}
.ext-hint{border:1.5px dashed #000;padding:14px 22px;font-size:12px;max-width:360px;line-height:1.6;}
.ext-hint b{font-weight:700;}
footer{position:absolute;bottom:24px;font-size:11px;color:#888;letter-spacing:1px;}
a{color:#000;}
</style>
</head>
<body>
  <div class="logo">DFG</div>
  <div class="sub">Browser • Monochrome</div>
  <div class="grid">
    <div class="wrap"><a class="tile" href="https://google.com">G</a><div class="label">Google</div></div>
    <div class="wrap"><a class="tile" href="https://youtube.com">▶</a><div class="label">YouTube</div></div>
    <div class="wrap"><a class="tile" href="https://github.com">⌥</a><div class="label">GitHub</div></div>
    <div class="wrap"><a class="tile" href="https://news.ycombinator.com">HN</a><div class="label">Hacker</div></div>
  </div>
  <div class="ext-hint">
    <b>Chrome Extensions Store</b><br>
    Нажмите на иконку пазла внизу, чтобы открыть Chrome Web Store и установить расширения как в Lemur Browser.
  </div>
  <footer>DFG BROWSER v1.0 • BLACK & WHITE</footer>
</body>
</html>
"""
}
