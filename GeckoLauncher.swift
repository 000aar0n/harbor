import Cocoa
import Security

@main
struct EloterApplication {
    static func main() {
        let app = NSApplication.shared
        let controller = GeckoLauncher()
        app.setActivationPolicy(.regular)
        app.delegate = controller
        withExtendedLifetime(controller) { app.run() }
    }
}

final class GeckoLauncher: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var backend: Process?
    let input = Pipe()
    let output = Pipe()
    var responseBuffer = Data()
    let status = NSTextField(labelWithString: "Starting Node.js backend…")
    let directButton = NSButton(title: "Open browser · Direct", target: nil, action: nil)
    let tunnelButton = NSButton(title: "Connect & open browser", target: nil, action: nil)
    let stopButton = NSButton(title: "Close browser", target: nil, action: nil)
    var running = false
    var backendReportedError = false
    var startupMarker: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--startup-check"), index + 1 < args.count {
            startupMarker = URL(fileURLWithPath: args[index + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 90) { exit(1) }
        }
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit eloter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem()
        menu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editItem.submenu = editMenu
        NSApp.mainMenu = menu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 570, height: 330), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "eloter · Gecko edition"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedWhite: 0.035, alpha: 1)
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 25, left: 25, bottom: 25, right: 25)
        let title = NSTextField(labelWithString: "eloter_")
        title.font = .monospacedSystemFont(ofSize: 28, weight: .medium)
        title.textColor = NSColor(calibratedRed: 0.4, green: 0.94, blue: 0.5, alpha: 1)
        root.addArrangedSubview(title)
        let subtitle = NSTextField(labelWithString: "Gecko / Firefox rendering · Node.js tunnel")
        subtitle.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        root.addArrangedSubview(subtitle)
        status.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 3
        root.addArrangedSubview(status)
        let row = NSStackView()
        row.spacing = 10
        directButton.target = self; directButton.action = #selector(openDirect)
        tunnelButton.target = self; tunnelButton.action = #selector(openTunnel)
        row.addArrangedSubview(directButton)
        row.addArrangedSubview(tunnelButton)
        root.addArrangedSubview(row)
        let secondRow = NSStackView()
        secondRow.spacing = 10
        secondRow.addArrangedSubview(NSButton(title: "Tunnel Setup…", target: self, action: #selector(importSettings)))
        stopButton.target = self; stopButton.action = #selector(stopBrowser)
        secondRow.addArrangedSubview(stopButton)
        root.addArrangedSubview(secondRow)
        let note = NSTextField(wrappingLabelWithString: "The browsing window is Firefox with a separate private profile. The tunnel covers web traffic; WebRTC/game media may connect directly.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        root.addArrangedSubview(note)
        window.contentView = root
        for view in [title, subtitle, status, row, secondRow, note] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -50).isActive = true
        }
        controls(enabled: false)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startBackend()
    }

    func controls(enabled: Bool) {
        directButton.isEnabled = enabled
        tunnelButton.isEnabled = enabled
        stopButton.isEnabled = enabled && running
    }

    func startBackend() {
        guard let resources = Bundle.main.resourceURL else { status.stringValue = "Missing application resources."; return }
        let worker = Process()
        worker.executableURL = resources.appendingPathComponent("runtime/node/bin/node")
        worker.arguments = [resources.appendingPathComponent("gecko/backend.mjs").path,
            "--runtime-dmg", resources.appendingPathComponent("runtime/Firefox.dmg").path,
            "--runtime-metadata", resources.appendingPathComponent("runtime/firefox.json").path,
            "--runtime-cache", FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("eloter/GeckoRuntime").path,
            "--home", resources.appendingPathComponent("gecko/home.html").path]
        worker.standardInput = input
        worker.standardOutput = output
        worker.standardError = startupMarker == nil ? FileHandle.nullDevice : FileHandle.standardError
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.receive(data) }
        }
        worker.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.controls(enabled: false)
                if self?.startupMarker != nil {
                    fputs("Node backend stopped before startup completed\n", stderr)
                    exit(1)
                }
                if self?.backendReportedError != true { self?.status.stringValue = "Backend stopped. Quit and reopen eloter." }
            }
        }
        do { try worker.run(); backend = worker }
        catch { status.stringValue = "Backend launch failed: " + error.localizedDescription }
    }

    func receive(_ data: Data) {
        responseBuffer.append(data)
        while let end = responseBuffer.firstIndex(of: 10) {
            let line = responseBuffer[..<end]
            responseBuffer.removeSubrange(...end)
            guard let value = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any], let type = value["type"] as? String else { continue }
            if startupMarker != nil { fputs("Backend event: " + type + "\n", stderr) }
            switch type {
            case "preparing":
                status.stringValue = "Preparing and verifying the Mozilla-signed Gecko runtime…"
            case "ready":
                controls(enabled: true)
                status.stringValue = "Gecko and Node.js ready."
                if let marker = startupMarker {
                    guard window.isVisible else { exit(1) }
                    do { try "eloter Gecko control window and Node backend ready\n".write(to: marker, atomically: true, encoding: .utf8); startupMarker = nil; NSApp.terminate(nil) }
                    catch { exit(1) }
                } else { launch(tunnel: false) }
            case "running":
                running = true
                controls(enabled: true)
                status.stringValue = value["tunnel"] as? Bool == true ? "Web tunnel enabled. Check the IP page in Firefox to verify." : "Direct browsing · Gecko / Firefox"
            case "stopped":
                running = false; controls(enabled: true)
                status.stringValue = value["message"] as? String ?? "Browser closed. Session data cleared."
            case "error":
                backendReportedError = true
                controls(enabled: true)
                status.stringValue = value["message"] as? String ?? "Backend error"
                if startupMarker != nil { fputs(status.stringValue + "\n", stderr); exit(1) }
            default: break
            }
        }
    }

    func send(_ value: [String: Any]) {
        guard backend?.isRunning == true else { status.stringValue = "Backend is unavailable."; return }
        do {
            var data = try JSONSerialization.data(withJSONObject: value)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        } catch { status.stringValue = error.localizedDescription; controls(enabled: true) }
    }

    @objc func openDirect() { launch(tunnel: false) }
    @objc func openTunnel() { launch(tunnel: true) }
    func launch(tunnel: Bool) {
        var command: [String: Any] = ["command": "launch", "tunnel": tunnel]
        if tunnel {
            guard let settings = TunnelSettings.load(), settings.url != nil else { importSettings(); return }
            command["endpoint"] = settings.endpoint
            command["token"] = settings.token
        }
        if running {
            let alert = NSAlert()
            alert.messageText = "Restart the browsing session?"
            alert.informativeText = "Changing the connection closes Firefox and clears this private session, including open tabs."
            alert.addButton(withTitle: "Restart browser")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        controls(enabled: false)
        status.stringValue = "Opening Gecko browser…"
        send(command)
    }
    @objc func stopBrowser() { controls(enabled: false); send(["command": "stop"]) }
    @objc func importSettings() {
        let panel = NSOpenPanel()
        panel.title = "Choose your eloter connection file"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let settings = try JSONDecoder().decode(TunnelSettings.self, from: Data(contentsOf: url))
            guard settings.url != nil else { throw NSError(domain: "eloter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid secure tunnel configuration."]) }
            try settings.save()
            status.stringValue = "Connection saved. Click Connect & open browser."
        } catch { status.stringValue = error.localizedDescription }
    }
    func applicationWillTerminate(_ notification: Notification) {
        output.fileHandleForReading.readabilityHandler = nil
        if backend?.isRunning == true { send(["command": "quit"]) }
        try? input.fileHandleForWriting.close()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil); return true
    }
}
