import Cocoa
import WebKit
import Network

@available(macOS 14.0, *)
final class Browser: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    var window: NSWindow!
    var web: WKWebView!
    let address = NSTextField(string: "")
    let status = NSTextField(labelWithString: "Direct connection")
    let container = NSView()
    let tunnelButton = NSButton(title: "Connect", target: nil, action: nil)
    var tunnel: HarborTunnel?
    var tunnelEnabled = false
    var proxyHost = ""
    var proxyPort: UInt16 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Secrét", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        let edit = NSMenuItem()
        menu.addItem(edit)
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", Selector(("cut:")), "x"), ("Copy", Selector(("copy:")), "c"), ("Paste", Selector(("paste:")), "v"), ("Select All", Selector(("selectAll:")), "a")] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        edit.submenu = editMenu
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1150, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Secrét"
        window.minSize = NSSize(width: 640, height: 420)
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        window.contentView = root
        let toolbar = NSStackView()
        toolbar.spacing = 8
        for (title, action) in [("←", #selector(back)), ("→", #selector(forward)), ("Reload", #selector(reload))] {
            toolbar.addArrangedSubview(NSButton(title: title, target: self, action: action))
        }
        address.placeholderString = "Search or enter a website"
        address.target = self
        address.action = #selector(go)
        address.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolbar.addArrangedSubview(address)
        toolbar.addArrangedSubview(NSButton(title: "Go", target: self, action: #selector(go)))
        tunnelButton.target = self
        tunnelButton.action = #selector(toggleTunnel)
        toolbar.addArrangedSubview(tunnelButton)
        toolbar.addArrangedSubview(NSButton(title: "Tunnel Setup…", target: self, action: #selector(importTunnel)))
        root.addArrangedSubview(toolbar)
        root.addArrangedSubview(status)
        root.addArrangedSubview(container)
        for view in [toolbar, status, container] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -20).isActive = true
        }
        status.font = .systemFont(ofSize: 11)
        replaceWebView()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func replaceWebView() {
        web?.stopLoading()
        web?.removeFromSuperview()
        let config = WKWebViewConfiguration()
        let store = WKWebsiteDataStore.nonPersistent()
        if proxyPort != 0 {
            let endpoint = NWEndpoint.hostPort(host: .init(proxyHost), port: .init(rawValue: proxyPort)!)
            var proxy = ProxyConfiguration(httpCONNECTProxy: endpoint)
            proxy.allowFailover = false
            store.proxyConfigurations = [proxy]
        }
        config.websiteDataStore = store
        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            web.topAnchor.constraint(equalTo: container.topAnchor),
            web.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        web.loadHTMLString("<html><body style='font:20px system-ui;padding:10%;color:#173344'><h1>Secrét</h1><p>Your WebKit browser.</p><p>Click Connect to browse through your encrypted US tunnel. Tunnel Setup imports your private connection file.</p><p>Browsing data is kept in memory for this session.</p></body></html>", baseURL: nil)
    }

    @objc func back() { web.goBack() }
    @objc func forward() { web.goForward() }
    @objc func reload() { web.reload() }
    @objc func go() {
        let text = address.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var value = text
        if !text.contains("://") {
            if !text.contains(" ") && (text.contains(".") || text.hasPrefix("localhost")) {
                value = "https://" + text
            } else {
                var search = URLComponents(string: "https://duckduckgo.com/")!
                search.queryItems = [URLQueryItem(name: "q", value: text)]
                value = search.url!.absoluteString
            }
        }
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            status.stringValue = "Enter an HTTP or HTTPS website."
            return
        }
        web.load(URLRequest(url: url))
    }

    @objc func importTunnel() {
        let panel = NSOpenPanel()
        panel.title = "Choose your Secrét connection file"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let settings = try JSONDecoder().decode(TunnelSettings.self, from: Data(contentsOf: url))
            guard settings.url != nil else { throw NSError(domain: "Harbor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid connection file. A secure wss:// endpoint and access token are required."]) }
            try settings.save()
            if tunnelEnabled { disconnectTunnel() }
            status.stringValue = "US tunnel ready. Click Connect."
        } catch { status.stringValue = "Setup failed: " + error.localizedDescription }
    }

    func disconnectTunnel() {
        tunnelEnabled = false
        tunnel?.stop()
        tunnel = nil
        proxyHost = ""
        proxyPort = 0
        replaceWebView()
        address.stringValue = ""
        status.stringValue = "Disconnected — direct browsing"
        tunnelButton.title = "Connect"
        tunnelButton.isEnabled = true
    }

    @objc func toggleTunnel() {
        if tunnelEnabled { disconnectTunnel(); return }
        guard let settings = TunnelSettings.load(), let endpoint = settings.url else {
            importTunnel()
            return
        }
        tunnelButton.isEnabled = false
        status.stringValue = "Starting encrypted US tunnel…"
        let bridge = HarborTunnel(endpoint: endpoint, token: settings.token)
        tunnel = bridge
        bridge.start { result in
            DispatchQueue.main.async {
                self.tunnelButton.isEnabled = true
                switch result {
                case .success(let port):
                    self.proxyHost = "127.0.0.1"
                    self.proxyPort = port
                    self.tunnelEnabled = true
                    self.tunnelButton.title = "Disconnect"
                    self.replaceWebView()
                    self.status.stringValue = "US tunnel enabled — checking browsing connection…"
                    self.web.load(URLRequest(url: URL(string: "https://api.ipify.org/?format=json")!))
                case .failure(let error):
                    self.status.stringValue = "Could not start tunnel: " + error.localizedDescription
                    bridge.stop()
                    self.tunnel = nil
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { tunnel?.stop() }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if tunnelEnabled, let url = navigationAction.request.url, url.scheme == "http" {
            if var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                parts.scheme = "https"
                if parts.port == 80 { parts.port = nil }
                if let secure = parts.url { webView.load(URLRequest(url: secure)) }
            }
            decisionHandler(.cancel)
        } else { decisionHandler(.allow) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        address.stringValue = webView.url?.absoluteString ?? ""
        window.title = webView.title ?? "Secrét"
        if tunnelEnabled, webView.url?.scheme == "https" {
            status.stringValue = "Connected • United States • Secrét browsing only"
            if webView.url?.host == "api.ipify.org" {
                webView.evaluateJavaScript("document.body.innerText") { value, _ in
                    guard self.tunnelEnabled, let text = value as? String,
                          let data = text.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                          let ip = object["ip"] else { return }
                    self.status.stringValue = "Connected • United States • IP: " + ip
                }
            }
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { status.stringValue = (tunnelEnabled ? "Tunnel browsing failed — direct fallback blocked. " : "") + error.localizedDescription }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        status.stringValue = (tunnelEnabled ? "Tunnel browsing failed — direct fallback blocked. " : "") + error.localizedDescription
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url, ["https", "http"].contains(url.scheme ?? "") {
            webView.load(navigationAction.request)
        }
        return nil
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct HarborApplication {
    static func main() {
        if #available(macOS 14.0, *) {
            let app = NSApplication.shared
            let browser = Browser()
            app.setActivationPolicy(.regular)
            app.delegate = browser
            app.run()
        } else {
            print("Secrét requires macOS 14 or later.")
        }
    }
}
