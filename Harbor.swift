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
    var proxyHost = ""
    var proxyPort: UInt16 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Harbor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        window.title = "Harbor Browser"
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
        toolbar.addArrangedSubview(NSButton(title: "Proxy…", target: self, action: #selector(proxy)))
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
        web.loadHTMLString("<html><body style='font:20px system-ui;padding:10%;color:#173344'><h1>Harbor</h1><p>Your WebKit browser.</p><p>Enter a website above, or configure your proxy first.</p><p>Browsing data is kept in memory for this session.</p></body></html>", baseURL: nil)
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

    @objc func proxy() {
        let alert = NSAlert()
        alert.messageText = "Proxy connection"
        alert.informativeText = "Enter your HTTP CONNECT proxy server. Authentication is not supported. Applying a setting clears this session’s cookies and history."
        let fields = NSStackView()
        fields.orientation = .vertical
        fields.frame = NSRect(x: 0, y: 0, width: 340, height: 60)
        let host = NSTextField(string: proxyHost)
        host.placeholderString = "Host, e.g. 127.0.0.1 (no http://)"
        let port = NSTextField(string: proxyPort == 0 ? "8080" : String(proxyPort))
        port.placeholderString = "Port"
        fields.addArrangedSubview(host)
        fields.addArrangedSubview(port)
        alert.accessoryView = fields
        alert.addButton(withTitle: "Use Proxy")
        alert.addButton(withTitle: "Use Direct Connection")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let h = host.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !h.isEmpty, !h.contains("://"), !h.contains("/"), !h.contains(where: { $0.isWhitespace }), let p = UInt16(port.stringValue), p > 0 else {
                status.stringValue = "Invalid proxy: enter a host and port from 1 to 65535."
                return
            }
            proxyHost = h
            proxyPort = p
        } else if response == .alertSecondButtonReturn {
            proxyHost = ""
            proxyPort = 0
        } else { return }
        replaceWebView()
        address.stringValue = ""
        status.stringValue = proxyPort == 0 ? "Direct connection" : "Proxy configured: \(proxyHost):\(proxyPort) — connection not yet verified"
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        address.stringValue = webView.url?.absoluteString ?? ""
        window.title = webView.title ?? "Harbor Browser"
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { status.stringValue = error.localizedDescription }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        status.stringValue = error.localizedDescription
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url, ["https", "http"].contains(url.scheme ?? "") {
            webView.load(navigationAction.request)
        }
        return nil
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

if #available(macOS 14.0, *) {
    let app = NSApplication.shared
    let browser = Browser()
    app.setActivationPolicy(.regular)
    app.delegate = browser
    app.run()
} else {
    print("Harbor requires macOS 14 or later.")
}
