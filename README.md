# Harbor

A small native Mac browser using Apple WebKit, with an optional HTTP CONNECT proxy connection. Requires macOS 14 or later. Works on Apple Silicon and Intel Macs.

## Download

Open [Releases](https://github.com/000aar0n/harbor/releases/latest) and download **Harbor-macOS.zip**. Extract it and open **Harbor.app** from your Downloads folder. No local build tools or administrator commands are needed to extract the app. Your Mac may require approval to run it.

This preview is ad-hoc signed, not notarized. The download is verified after ZIP extraction during the build. It cannot override Gatekeeper, Santa, or other management policies.

## Features

- Address and search bar, back/forward, reload.
- Session-only cookies and browsing data.
- Optional HTTP CONNECT proxy, with automatic direct-connection failover disabled.

No proxy server or VPN subscription is included. The app does not have a built-in US endpoint, support Chrome/Firefox extensions, or provide a system-wide VPN. Proxy authentication is not implemented. Changing proxy settings clears the browsing session.

## Build

On a Mac with Apple developer tools installed, run `bash build-macos.sh`.

The GitHub workflow builds both architectures, creates the app metadata, signs the bundle, checks the signature, archives and extracts it, checks the extracted signature, and checks startup on the build Mac. Only a successful build is published as a Release. This does not establish that all browser features or a particular proxy server work; those need separate testing.
