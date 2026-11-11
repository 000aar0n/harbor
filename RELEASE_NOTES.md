Secrét 0.2.1 renames Harbor to Secrét throughout the app, menus, and Mac bundle. The encrypted US browsing tunnel and existing connection files remain compatible.

Download Secret-macOS.zip, extract it, and open Secrét.app. Import your private Harbor-Connection.json with Tunnel Setup, then click Connect.

To remove the download quarantine after extracting into Downloads, run in Terminal on your Mac:

xattr -dr com.apple.quarantine "$HOME/Downloads/Secrét.app"
open "$HOME/Downloads/Secrét.app"

Requires macOS 14 or later. Supports Apple Silicon and Intel. The preview is ad-hoc signed and not notarized. xattr does not override device management policies. The tunnel covers Secrét browsing only. Free Render hosting may take time to wake up.
