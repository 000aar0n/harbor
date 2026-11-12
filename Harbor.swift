import Cocoa
import WebKit
import Network

@available(macOS 14.0, *)
final class Browser: MouseCaptureDelegate, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var web: WKWebView!
    let address = NSTextField(string: "")
    let searchEngine = NSPopUpButton(frame: .zero, pullsDown: false)
    let status = NSTextField(labelWithString: "Direct connection")
    let container = NSView()
    let tunnelButton = NSButton(title: "Connect", target: nil, action: nil)
    var tunnel: HarborTunnel?
    var tunnelEnabled = false
    var startupCheckURL: URL?
    var proxyHost = ""
    var proxyPort: UInt16 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        approveMouseCapture = { [weak self] view in
            guard let self = self, view === self.web else { return false }
            return MouseCaptureDelegate.isInteractiveSecurePage(view)
        }
        mouseCaptureChanged = { [weak self] captured in
            self?.status.stringValue = captured ? "Mouse captured — press Esc to release" : "Mouse released"
        }
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit eloter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        window.title = "eloter"
        window.minSize = NSSize(width: 1040, height: 500)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedWhite: 0.025, alpha: 1)
        window.titlebarAppearsTransparent = true
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 12
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.025, alpha: 1).cgColor
        root.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        window.contentView = root
        let toolbar = NSStackView()
        toolbar.spacing = 6
        let brand = NSTextField(labelWithString: "eloter_")
        brand.font = .monospacedSystemFont(ofSize: 16, weight: .bold)
        brand.textColor = NSColor(calibratedRed: 0.35, green: 0.95, blue: 0.48, alpha: 1)
        toolbar.addArrangedSubview(brand)
        for (title, action) in [("←", #selector(back)), ("→", #selector(forward)), ("Reload", #selector(reload)), ("Home", #selector(home))] {
            toolbar.addArrangedSubview(NSButton(title: title, target: self, action: action))
        }
        searchEngine.addItems(withTitles: ["Bing", "Google", "DuckDuckGo"])
        searchEngine.toolTip = "Search engine — switch if a provider is unavailable"
        searchEngine.selectItem(withTitle: UserDefaults.standard.string(forKey: "searchEngine") ?? "Bing")
        searchEngine.target = self
        searchEngine.action = #selector(changeSearchEngine)
        toolbar.addArrangedSubview(searchEngine)
        address.placeholderString = "Search or enter a website"
        address.target = self
        address.action = #selector(go)
        address.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolbar.addArrangedSubview(address)
        toolbar.addArrangedSubview(NSButton(title: "Go", target: self, action: #selector(go)))
        tunnelButton.target = self
        tunnelButton.action = #selector(toggleTunnel)
        toolbar.addArrangedSubview(tunnelButton)
        toolbar.addArrangedSubview(NSButton(title: "Setup", target: self, action: #selector(importTunnel)))
        toolbar.addArrangedSubview(NSButton(title: "Safari ↗", target: self, action: #selector(openInSafari)))
        for case let button as NSButton in toolbar.arrangedSubviews {
            button.bezelStyle = .regularSquare
            button.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            button.contentTintColor = NSColor(calibratedRed: 0.42, green: 0.9, blue: 0.52, alpha: 1)
        }
        address.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        address.backgroundColor = NSColor(calibratedWhite: 0.065, alpha: 1)
        address.textColor = NSColor(calibratedWhite: 0.9, alpha: 1)
        address.focusRingType = .none
        searchEngine.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        container.wantsLayer = true
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(calibratedWhite: 0.16, alpha: 1).cgColor
        root.addArrangedSubview(toolbar)
        root.addArrangedSubview(status)
        root.addArrangedSubview(container)
        for view in [toolbar, status, container] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -20).isActive = true
        }
        status.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        status.textColor = NSColor(calibratedRed: 0.42, green: 0.75, blue: 0.49, alpha: 1)
        replaceWebView()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func replaceWebView() {
        web?.stopLoading()
        web?.removeFromSuperview()
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true
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
        home()
    }

    @objc func home() {
        let engine = searchEngine.titleOfSelectedItem ?? "Bing"
        let endpoint = engine == "Google" ? "https://www.google.com/search" : engine == "DuckDuckGo" ? "https://duckduckgo.com/" : "https://www.bing.com/search"
        let mode = tunnelEnabled ? "US tunnel enabled" : "Direct browsing"
        web.loadHTMLString("""
        <!doctype html><html lang="en"><head><title>eloter</title><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        :root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#080a08;color:#c4cec5;font:14px ui-monospace,SFMono-Regular,Menlo,monospace;line-height:1.7}
        main{max-width:780px;margin:14vh auto;padding:32px}header{display:flex;justify-content:space-between;align-items:center;border-bottom:1px solid #263329;padding-bottom:18px;color:#82a689;font-size:12px}
        h1{font-size:48px;font-weight:500;letter-spacing:-3px;color:#75ee8b;margin:52px 0 4px}p{color:#839086;margin:0 0 32px}form{display:flex;align-items:center;border:1px solid #35523d;background:#0d130e;padding:6px 8px 6px 16px;gap:12px}label{color:#75ee8b}input{min-width:0;flex:1;background:transparent;color:#e2ebe3;border:0;padding:12px 0;font:inherit;outline:none}form:focus-within{border-color:#75ee8b}button{background:#17291b;color:#9cf3ac;border:1px solid #34553c;padding:10px 16px;font:inherit;cursor:pointer}button:hover{background:#23402a}nav{display:flex;gap:26px;padding:24px 0}a{color:#8eb597;text-decoration:none}a:hover{color:#a7ffb6;text-decoration:underline}footer{margin-top:72px;border-top:1px solid #263329;padding-top:18px;color:#5f7864;font-size:11px}input:focus-visible,button:focus-visible,a:focus-visible{outline:1px solid #75ee8b;outline-offset:4px}@media(max-width:600px){main{margin:8vh auto;padding:22px}h1{font-size:40px}header{gap:20px}button{padding:10px}}
        </style></head><body><main>
        <header><span>eloter / browser</span><span>\(mode)</span></header>
        <h1>eloter_</h1><p>A quiet place to search.</p>
        <form action="\(endpoint)" method="get"><label for="q">&gt;</label><input id="q" name="q" type="search" placeholder="Search with \(engine)" aria-label="Search with \(engine)" required autocomplete="off"><button type="submit">Search ↵</button></form>
        <nav aria-label="Quick links"><a href="https://www.wikipedia.org/">Wikipedia ↗</a><a href="https://github.com/">GitHub ↗</a><a href="https://api.ipify.org/?format=json">Check IP ↗</a></nav>
        <footer>Connect in the toolbar to use your US browsing tunnel.</footer>
        </main></body></html>
        """, baseURL: nil)
        address.stringValue = ""
        window.title = "eloter"
    }

    @objc func openInSafari() {
        guard let url = web.url, ["http", "https"].contains(url.scheme ?? "") else {
            status.stringValue = "Open a website first, then use Safari for passkey sign-in."
            return
        }
        let alert = NSAlert()
        alert.messageText = "Open this site in Safari?"
        alert.informativeText = "Safari supports passkeys. This opens a separate browsing session outside eloter’s tunnel."
        alert.addButton(withTitle: "Open in Safari")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Safari.app"), configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error = error { DispatchQueue.main.async { self.status.stringValue = error.localizedDescription } }
        }
    }

    @objc func back() { web.goBack() }
    @objc func forward() { web.goForward() }
    @objc func reload() { web.reload() }
    @objc func changeSearchEngine() {
        UserDefaults.standard.set(searchEngine.titleOfSelectedItem ?? "Bing", forKey: "searchEngine")
        status.stringValue = "Search engine: " + (searchEngine.titleOfSelectedItem ?? "Bing")
        if web.url == nil || web.url?.scheme == "about" { home() }
    }
    @objc func go() {
        let text = address.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var value = text
        if !text.contains("://") {
            if !text.contains(" ") && (text.contains(".") || text.hasPrefix("localhost")) {
                value = "https://" + text
            } else {
                let engine = searchEngine.titleOfSelectedItem ?? "Bing"
                let endpoint = engine == "Google" ? "https://www.google.com/search" : engine == "DuckDuckGo" ? "https://duckduckgo.com/" : "https://www.bing.com/search"
                var search = URLComponents(string: endpoint)!
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
        panel.title = "Choose your eloter connection file"
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
        window.title = webView.title ?? "eloter"
        if let marker = startupCheckURL {
            startupCheckURL = nil
            webView.evaluateJavaScript("document.querySelector('input[name=q]') !== null") { value, error in
                guard error == nil, value as? Bool == true, self.window.isVisible else {
                    fputs("Startup check failed: home window did not render\n", stderr)
                    exit(1)
                }
                do {
                    try "eloter home window rendered\n".write(to: marker, atomically: true, encoding: .utf8)
                    NSApp.terminate(nil)
                } catch {
                    fputs("Startup check could not write its marker\n", stderr)
                    exit(1)
                }
            }
        }
        if tunnelEnabled, webView.url?.scheme == "https" {
            status.stringValue = "Connected • United States • eloter browsing only"
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
            if let index = CommandLine.arguments.firstIndex(of: "--startup-check"), index + 1 < CommandLine.arguments.count {
                browser.startupCheckURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                    fputs("Startup check timed out\n", stderr)
                    exit(1)
                }
            }
            withExtendedLifetime(browser) { app.run() }
        } else {
            print("eloter requires macOS 14 or later.")
        }
    }
}
