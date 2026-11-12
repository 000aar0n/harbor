# eloter for Chrome

A clearly branded Manifest V3 extension plus a Node.js companion for the existing authenticated Render WebSocket tunnel. No replacement browser, Apple Silicon binary, or xattr command is needed. Node.js 24.5+ works on Apple Silicon and Intel; the extension uses your installed Chrome engine.

## Quick start

Use only where Chrome extensions, Node, and your tunnel are permitted. Managed-device policies remain enforced. If any step is blocked by policy, ask your administrator to approve the project.

1. Extract `eloter-Chrome.zip` completely. Keep its `extension` and `companion` folders.
2. In Chrome, open `chrome://extensions`. If developer extensions are permitted, enable Developer mode, choose **Load unpacked**, and select the extracted **extension** folder. Do not select the ZIP or its parent folder. Pin **eloter tunnel** using Chrome's Extensions menu.
3. Install an approved Node.js 24.5+ runtime from https://nodejs.org if you do not already have it. The download includes the pinned `ws` dependency, so no npm installation is required for the release ZIP.
4. Open Terminal in the extracted **companion** folder. Run:

   ```sh
   node bridge.mjs --config "$HOME/Downloads/Harbor-Connection.json"
   ```

   Use the actual path to your private connection JSON. It must contain `endpoint` (a `wss://…/tunnel` URL) and `token`. Keep the file private; it is deliberately absent from this public download. Obtain it privately from your existing tunnel setup if needed. Do not paste its token into chat or commit it to GitHub.
5. Leave Terminal open. In the extension, click **Connect**. Reload the site you want to use, then click **Check browsing IP** to verify your Render exit IP. The first request can take longer if Render is waking up.
6. Click **Disconnect** before closing Terminal to restore Chrome's underlying proxy settings. If Terminal closes early, new proxied web requests fail until you disconnect or restart the companion.

## What it does

Chrome's standard proxy API sends regular-profile HTTP/HTTPS web requests to `127.0.0.1:8877`. The companion opens authenticated TLS WebSockets to your existing Render tunnel, which connects to public destinations on ports 80 and 443. HTTPS uses CONNECT and remains encrypted between Chrome and the destination. Plain HTTP is visible to the tunnel operator. No certificate installation or HTTPS interception is used.

Your websites run as normal pages in Chrome, preserving their actual origins. Chrome handles passkeys, pointer lock, and fullscreen through its normal permissions. This does not establish that every site, passkey provider, or cloud game works through the proxy.

This is **not a full VPN**. It does not cover other apps, incognito, WebRTC/UDP or every DNS path. Existing network connections may persist until tabs reload or Chrome restarts. Some websites reject shared data-center IPs. Chrome URL restrictions, extension restrictions, and device security controls remain in force. It cannot guarantee access to all websites. The extension refuses to change settings controlled by policy or another extension. Disconnect clears only this extension's proxy layer.

There is no direct fallback in the proxy configuration. The ON badge means Chrome is configured to use the companion; it does not certify the remote tunnel is online. Check the IP and reload a website to verify. A wrong/expired token or unavailable Render service can leave requests waiting or failing; disconnect restores normal underlying settings.

## Development and checks

```sh
npm ci --prefix companion --ignore-scripts
npm --prefix companion test
# Requires Python Playwright plus an extension-capable Chromium:
python tests/browser-smoke.py
python package.py
```

Tests cover authenticated binary CONNECT, ordinary HTTP request rewriting and body forwarding, invalid configurations/headers, local health endpoint restrictions, managed-policy refusal, other-extension refusal, and restoring the underlying proxy layer. The Chromium smoke test loads the real extension, routes a page through a controlled WebSocket fixture, stops the companion to verify new requests fail, and disconnects.

The extension requests only `proxy` and loopback host access. It has no content scripts, page/history access, analytics, token storage, or remote code. Its health endpoint is read-only and checks its Host header. The companion binds only to loopback. The existing Render server validates public destinations and authenticates clients. Neither extension nor companion logs browsing URLs or tokens.

Source installs exclude dependencies: run `npm ci --prefix companion --ignore-scripts`. Release ZIPs include the pinned `ws` package and its license. Never package your private connection JSON.
