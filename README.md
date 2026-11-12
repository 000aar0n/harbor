# Secrét

A native Mac WebKit browser with an encrypted, authenticated US browsing tunnel. Requires macOS 14 or later; supports Apple Silicon and Intel.

## Use

1. Download **Secret-macOS.zip** from [Releases](https://github.com/000aar0n/harbor/releases/latest), extract it, and open Secrét.app.
2. Click **Tunnel Setup…** and select your private **Harbor-Connection.json** file. Secrét saves its access key in macOS Keychain. Keep this file private; it grants access to your server.
3. Click **Connect**. Secrét loads an IP-check page through the tunnel. The status displays your US browsing IP after a successful response.
4. Browse normally. **Disconnect** explicitly returns to direct browsing and clears the session. Connecting, disconnecting, and importing settings clear session cookies and history.

The tunnel covers HTTP CONNECT web traffic within Secrét and upgrades HTTP navigations to HTTPS. It is not a system VPN, does not affect other applications, and does not provide country selection. It does not claim to tunnel arbitrary UDP or WebRTC traffic. Non-HTTPS sites may not work. WebKit direct proxy failover is disabled: an unavailable tunnel produces a browsing error. The button enables routing; the connected label appears only after a page loads through it.

## Search

Type a query in the address bar and press Return. Bing is the default search engine. The toolbar selector also offers Google and DuckDuckGo and remembers your choice. If a search provider rejects the shared tunnel IP, choose another engine and submit your query again.

## Server

Render runs `server/tunnel.py` with `pip install -r server/requirements.txt` and `python server/tunnel.py`. Set `HARBOR_TOKEN` to a random secret of at least 32 characters. The authenticated `/tunnel` WebSocket forwards binary streams to public destinations on ports 80 and 443. DNS resolves on the server; private, reserved, and link-local destinations are rejected and validated addresses are pinned for connection. No destination or access logs are recorded by the application. Render and destination websites have their own infrastructure logs.

Connection file format (never commit real tokens):

```json
{"endpoint":"wss://YOUR-SERVICE.onrender.com/tunnel","token":"YOUR-PRIVATE-ACCESS-TOKEN-AT-LEAST-32-CHARACTERS"}
```

The free Render plan can sleep when idle and take time to wake. Failed requests can be retried without disconnecting. Bandwidth counts toward your Render allowance. Rotate access by replacing `HARBOR_TOKEN` on Render and importing a new connection file.

## Build and validation

On macOS, run `bash build-macos.sh`. GitHub Actions builds both architectures, checks signing and packaged startup, exercises actual WebKit HTTPS traffic through the WebSocket server, and verifies that stopping the tunnel blocks subsequent browsing. A successful workflow publishes the app. Server tests: `python3 -m unittest discover -s tests -v` after installing server requirements.

This preview is ad-hoc signed, not notarized. Your Mac may require approval to run it. The app cannot override Gatekeeper or device management policies.

## Opening the downloaded app with xattr

After extracting Secret-macOS.zip in Downloads, run these commands in Terminal on your Mac:

```sh
xattr -dr com.apple.quarantine "$HOME/Downloads/Secrét.app"
open "$HOME/Downloads/Secrét.app"
```

This removes the downloaded app's quarantine attribute. It does not notarize the app or override device management policies. If you extracted it somewhere else, use that app's path instead. The existing Harbor connection file remains compatible.

## Passkeys

The current ad-hoc signed build cannot enable arbitrary-site passkeys inside WebKit. Apple requires an organization Apple Developer account and approval for `com.apple.developer.web-browser.public-key-credential`: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential

Use the Safari button to open the current site in Safari for passkey sign-in. Safari uses its own session and is outside Secrét’s tunnel. This does not sign you into the site within Secrét.

## Gaming and mouse capture

WebKit fullscreen is enabled. On a secure game page, click the game and approve its mouse-capture request. WebKit handles cursor hiding and relative mouse movement; Escape releases capture. Authorization is implemented through WebKit’s non-public Objective-C delegate selectors, isolated in MouseCapture.swift; these selectors may change in future macOS releases. The Mac workflow tests actual pointer lock and unlock.

GeForce NOW/Fortnite streaming has not been verified. Browser support and streaming transport are controlled by NVIDIA and WebKit. The Render browsing tunnel does not tunnel UDP/WebRTC game streams, so it cannot be treated as a gaming VPN.
