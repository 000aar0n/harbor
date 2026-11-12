Secrét 0.2.3 fixes unreliable searches through the browsing tunnel by defaulting to Bing and adding a search-engine selector in the toolbar. Choose Bing, Google, or DuckDuckGo; your choice is saved for the next launch. Search providers may restrict shared server IP addresses; switch providers if one is unavailable.

Download Secret-macOS.zip and replace the previous app with Secrét.app. Your tunnel connection file remains compatible.

Adds a minimal black-and-green interface, a searchable home page, quick links, and an Open in Safari button for passkey sign-in in Safari. Safari uses a separate session outside Secrét’s tunnel. Native in-app passkeys still require Apple’s browser entitlement.

After extracting into Downloads, run on your Mac:
xattr -dr com.apple.quarantine "$HOME/Downloads/Secrét.app"
open "$HOME/Downloads/Secrét.app"

Requires macOS 14 or later. The preview is ad-hoc signed and not notarized. The tunnel covers Secrét browsing only.

Enables WebKit fullscreen and mouse capture for games. When a game asks, click Allow; press Escape to release the mouse. Pointer-lock authorization uses WebKit’s non-public delegate bridge and may vary by macOS release. GeForce NOW/Fortnite streaming itself has not been verified.
