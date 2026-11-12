# eloter — Gecko edition

A custom macOS launcher and browsing-tunnel controller powered by **Node.js**, with an **actual Firefox/Gecko browser runtime**. The launcher does not link WebKit, Electron, Chromium, or NW.js. Browsing happens in Firefox's own window and tab interface; the separate native eloter panel controls the connection.

## Use

Download eloter-Gecko-AppleSilicon.zip from Releases, extract it, and open eloter.app. No separate Node or Firefox installation is required. On first launch, the launcher verifies and prepares the bundled Mozilla-signed Firefox runtime, then opens it with a separate private session.

- **Open browser · Direct** starts direct browsing.
- **Tunnel Setup…** imports your existing Harbor-Connection.json and keeps its access key in macOS Keychain.
- **Connect & open browser** restarts the private session using the authenticated encrypted web tunnel and opens the IP-check page. Verify the IP in that page.
- **Close browser** closes the owned Firefox session. Quitting eloter also closes that session. Switching modes clears its cookies, tabs, and session profile.

The browser retains Firefox's own identity, security settings, permission handling, fullscreen, and pointer-lock implementation. A black-and-green userChrome stylesheet and local home page theme the dedicated session. The browser runtime remains Mozilla-signed and separate from any installed personal Firefox session.

## Runtime and packaging

The native arm64 launcher is Swift/AppKit. The JavaScript backend uses pinned `ws` and Node.js LTS to bridge loopback HTTP CONNECT streams to authenticated TLS WebSockets. Production accepts only secure wss endpoints. Proxy failover to direct browsing is disabled. HTTPS-only navigation is enabled in this private profile. The server rejects private/reserved destinations and accepts public web ports only.

The package includes official Firefox 160.0 and Node.js v26.13.1 downloads, verified against their official published checksums. Firefox's original application, license notices, and Developer ID signature are preserved in its official DMG. At first use it is copied to `~/Library/Application Support/eloter/GeckoRuntime` and verified against the original Apple-anchored Mozilla signing requirement. Running the copy outside the launcher bundle lets Firefox updates keep working without invalidating the launcher's signature. Node retains its upstream signature and JIT entitlements. Node and the launcher run natively on Apple Silicon; Mozilla's official Mac runtime is universal and includes native arm64.

This download is substantially larger than the previous WebKit edition. Requires an Apple Silicon Mac; macOS 26 is tested. The launcher is ad-hoc signed and not notarized. Managed-device approval requirements are unchanged. An engine change does not establish the cause of earlier unexplained terminations.

## Limits

The tunnel covers browser web traffic, not all device traffic or UDP/WebRTC media. Game streams may connect directly. GeForce NOW/Fortnite compatibility has **not** been verified; NVIDIA controls which browsers it supports. Firefox handles passkey availability and platform prompts; actual credential registration/sign-in has not been tested here.

## Build and checks

On Apple Silicon macOS with Apple developer tools, npm, and Python available:

```sh
bash build-gecko-macos.sh
```

The build downloads pinned official runtimes, checks their hashes, creates the custom icon, and signs and verifies the launcher package. It does not alter Mozilla's signed application. GitHub Actions tests the Node byte tunnel, verifies launcher and backend startup through both direct execution and LaunchServices, drives the real Firefox engine to render search results, checks pointer capture and release, verifies Gecko traffic through the Node tunnel, and checks that a stopped proxy blocks browsing.

The older WebKit source remains in the repository for history but is not compiled or packaged into the Gecko edition. The Render server protocol and existing connection files remain compatible.
