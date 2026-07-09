# Tickr

Native macOS stock monitor — prices, charts, favorites, themes. Built autonomously
by the mm-fac software factory (Codex Cloud + Claude Code lanes behind a
deterministic supervisor). Scaffold generated 2026-07-09.

- macOS 14+, SwiftUI + Swift Charts, XcodeGen (`xcodegen generate` → open `Tickr.xcodeproj`)
- `TickrCore/` — platform-agnostic domain package (`swift test --package-path TickrCore`)
- Market data: user-supplied API key at runtime (never in the repo)
