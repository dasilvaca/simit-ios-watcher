# SappaWidget (screen 7)

WidgetKit extension code: small (status or "N días" to pay with discount), medium (one row per
vehicle) and lock-screen (rectangular/inline). It reads `widget-snapshot.json`, which the app writes
to the App Group container after every run (`CheckService.writeSnapshot`). It never opens SQLite.

**Not wired into the project yet.** The project uses Xcode 27's `project.xcproj` text format, and the
key for the "Embed Foundation Extensions" copy phase could not be determined from the command line
(unknown keys are silently ignored), so adding the target is one manual step:

1. Xcode → File → New → Target → Widget Extension, name `SappaWidget`, uncheck "Include
   Configuration App Intent" and Live Activity. When Xcode creates its own `SappaWidget/` folder,
   delete its generated Swift files and keep this folder's `SappaWidget.swift` and
   `Localizable.xcstrings` as the target's sources.
2. Bundle id: `<app bundle id>.widget`. Add the App Group `group.<app bundle id>` to the widget
   (same as `Config/Sappa.entitlements`).
3. Add `Sappa/Resources/Fonts/SpaceGrotesk.ttf` to the widget target and `UIAppFonts` to its Info.plist.

The code was compiled in an app-extension target during development (build succeeded).
