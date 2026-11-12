eloter 0.3.1 changes the browser engine from WebKit to actual Gecko/Firefox and moves the browsing tunnel backend to Node.js.

Download eloter-Gecko-AppleSilicon.zip, extract it, and open eloter.app. The package includes the Firefox runtime and Node.js; no separate installation is required. First launch prepares the Mozilla-signed runtime in eloter's application-support folder. Firefox uses a separate private profile. Browsing uses Firefox's window and tabs; the eloter control panel provides direct/tunneled launch and connection setup. Existing Harbor-Connection.json files remain compatible.

The native launcher and Node runtime are arm64. Mozilla's official Firefox Mac runtime includes native arm64. The download is substantially larger. Firefox retains its own signature and identity. The launcher is ad-hoc signed and not notarized; school/work management approval requirements remain unchanged.

The web tunnel does not cover UDP/WebRTC game media. NVIDIA currently lists Firefox support for GeForce NOW on Windows only; macOS GeForce NOW/Fortnite compatibility and real passkey sign-in remain unverified. This release does not claim that changing engines resolves earlier unexplained system terminations.
