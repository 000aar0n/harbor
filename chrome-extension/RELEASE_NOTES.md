eloter 0.4.0 runs as a clearly branded Chrome extension with a small Node.js companion for the existing authenticated Render tunnel. It replaces the need to launch the custom macOS browser.

- Connect/Disconnect controls, black/green interface and original compass icon.
- Standard Chrome proxy API; refuses settings controlled by administrator policy or another extension.
- Regular-profile HTTP/HTTPS web traffic on ports 80/443. No direct fallback for new proxied requests if the companion stops. Disconnect restores Chrome's underlying settings.
- The ZIP includes the pinned Node dependency; install an approved Node.js 22+ runtime, start the companion with your private Harbor-Connection.json, and load the extension folder through Chrome's permitted development-extension flow. Detailed instructions are inside README.md.

This is not a full VPN and cannot guarantee access to every website. It does not bypass school/device policies. Incognito, WebRTC/UDP and other apps are outside its guarantee. The badge reflects proxy configuration; use Check browsing IP to verify the actual exit. Private credentials are deliberately excluded from the download. Do not run xattr or install certificates for this edition.
