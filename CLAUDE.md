# Project rules — SetupRush Trader

## Release checklist (every release, no exceptions)

1. **Build verification first.** Run `swift build` (debug) and confirm a clean compile
   before touching version numbers, README, or git. Never tag/release on top of an
   unverified change.
2. **Version bump, in two places that must always match:**
   - `AppPackaging/Info.plist` — `CFBundleShortVersionString` and `CFBundleDisplayName`.
   - The in-app version badge (header, e.g. "BETA 0.2") in `ContentView.swift`.
3. **Rebuild the release `.app`** via `AppPackaging/make_app.sh` *after* the version bump,
   so the packaged bundle actually reflects the new code and new version before it's
   zipped/uploaded.
4. **Refresh `README.md`:**
   - Replace `docs/screenshot.png` with a current screenshot of the running app.
   - Update the feature list to reflect what's actually shipped — add what's new, remove
     what's no longer true. Don't let it drift from reality.
   - Keep it in a professional GitHub-README style: enough to orient a new reader in
     under a minute. Not a changelog dump, not a one-liner — balanced.
5. **Commit, tag, push, release:** commit the version bump + README update together, tag
   `vX.Y.Z`, push the tag, and create/update the GitHub release with the new `.app` zip
   attached and notes describing what changed since the last release.

Skipping step 1 or 2 is the specific failure mode this checklist exists to prevent: never
ship a release with a stale build or an unbumped version number.
