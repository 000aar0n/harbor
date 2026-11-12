goonson 0.2.5 renames the app, menus, home page, and download package. The application identity and existing tunnel setup remain compatible.

Download goonson-macOS.zip, extract it, and open goonson.app.

Launch verification now checks that the actual home window renders, both when starting the executable and when opening the packaged app through LaunchServices. The application delegate is explicitly retained for the application lifetime. The release checks run on macOS 26 and build a universal executable for Intel and Apple Silicon.

This preview is ad-hoc signed and not notarized. Renaming does not change approval requirements on managed devices. Requires macOS 14 or later.
