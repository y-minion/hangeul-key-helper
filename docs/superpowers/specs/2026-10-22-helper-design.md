# 한영키 도우미 v0.1

## Intent and authorization
The user wants the already-discussed six-step macOS helper built, so non-developers can apply their blog's Caps Lock → F18 → previous input source workflow. Their request authorizes implementation of that described helper. No host keyboard mutation is needed to build it.

## Design decisions
- Standalone Swift/AppKit macOS app, Korean UI, macOS 13+ deployment target, no dependencies or event taps. A copied, short-lived helper reapplies at login; no persistent input-monitoring process.
- Read and write using Apple's /usr/bin/hidutil, restricted to keyboard services. Parse actual property output; malformed/ambiguous state fails closed. If keyboards have different mapping arrays, do not write to any of them in v0.1.
- Preserve unrelated mappings, reject conflicting Caps Lock mappings. Save an atomic backup before the first change. Restore only this tool's Caps Lock change while retaining later unrelated mappings. Existing F18 mapping remains on restore (the app did not create it).
- Login helper is stored in ~/Library/Application Support/HangeulKeyHelper. LaunchAgent uses absolute executable paths, RunAtLoad only; no KeepAlive or polling. Registration checks errors. Reinstall keeps original backup.
- Known old blog LaunchAgent com.user.capslock.plist is detected and explained; never removed silently. Only one automation should own the mapping. Existing third-party apps are not killed or uninstalled.
- Manual system shortcut setup, fallback settings instructions, local typing test. A mapped key and a working input source shortcut are separate statuses; never claim end-to-end success merely from hidutil output.
- Restore stops owned automation and returns owned Caps mapping to pre-install state. Keep recovery metadata if any step fails; disconnected-device and mixed-mapping limitations documented.
- No telemetry, no network, no sudo, no automated privacy permission changes. Settings navigation only via NSWorkspace, no Apple Events.
- Ship source, locally runnable universal .app and zip, build/sign/notarize instructions and CI. Developer ID/notarization cannot be claimed without real credentials.

## Verification
Automated mapping, parser, persistence and lifecycle tests use temporary home directories and a fake keyboard/launcher. Real macOS read-only diagnostics, universal build, app UI review in demo/read-only mode. Actual keyboard mutation, restart/reconnect and user typing remain manual acceptance checks.
