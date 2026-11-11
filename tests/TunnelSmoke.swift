import Cocoa
import WebKit
import Network

@main
final class TunnelSmoke: NSObject, WKNavigationDelegate {
    static var instance: TunnelSmoke!
    var bridge: HarborTunnel!
    var web: WKWebView!
    var checkingFailure = false
    static func main() {
        _ = NSApplication.shared
        instance = TunnelSmoke()
        instance.run()
        RunLoop.main.run()
    }
    func run() {
        bridge = HarborTunnel(endpoint: URL(string: "ws://127.0.0.1:18765/tunnel")!, token: "test-only-token-not-a-real-secret-123456789")
        bridge.start { result in
            DispatchQueue.main.async {
                guard case .success(let port) = result else { self.fail("Listener did not start"); return }
                let store = WKWebsiteDataStore.nonPersistent()
                var proxy = ProxyConfiguration(httpCONNECTProxy: .hostPort(host: "127.0.0.1", port: .init(rawValue: port)!))
                proxy.allowFailover = false
                store.proxyConfigurations = [proxy]
                let config = WKWebViewConfiguration()
                config.websiteDataStore = store
                self.web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
                self.web.navigationDelegate = self
                self.web.load(URLRequest(url: URL(string: "https://example.com/")!))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 80) { self.fail("Timed out") }
    }
    func fail(_ message: String) { fputs(message + "\n", stderr); exit(1) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if checkingFailure { fail("Direct fallback occurred after tunnel stopped"); return }
        webView.evaluateJavaScript("document.body.innerText") { value, error in
            guard let text = value as? String, text.contains("Example Domain") else { self.fail("Tunnel did not deliver destination content"); return }
            print("PASS: WebKit HTTPS traffic crossed the authenticated WebSocket tunnel")
            self.checkingFailure = true
            self.bridge.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.web.load(URLRequest(url: URL(string: "https://www.iana.org/help/example-domains?harbor-smoke=1")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
            }
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if checkingFailure { print("PASS: Failed tunnel blocks browsing instead of falling back"); exit(0) }
        fail("HTTPS tunnel failed: " + error.localizedDescription)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if checkingFailure { print("PASS: Failed tunnel blocks browsing"); exit(0) }
        fail(error.localizedDescription)
    }
}
