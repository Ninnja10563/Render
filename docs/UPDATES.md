# Update delivery

Render uses [Sparkle 2.10.0](https://sparkle-project.org/documentation/) for native automatic checks, verified downloads, installation and relaunch. The app menu has Check for Updates; Settings → Updates controls daily checking and automatic downloads/installation. Sparkle owns these persisted preferences; launch does not overwrite a user’s choice. Automatic downloads install when the app quits. Interactive installation requests a normal macOS quit, so Render’s export and unsaved-project guards still apply.

The update channel carries Render development prereleases. There is no separate stable channel yet. The first updater-enabled version must be installed manually; older versions cannot discover it automatically.

## Release path

1. The existing release workflow builds/tests the app, installs and launches the DMG copy, exercises native input, and captures both appearances.
2. `scripts/test-updates.sh` builds Sparkle’s pinned command-line test driver, creates disposable app copies and test-only keys, rejects a forged feed and corrupt archive, performs an actual update, verifies its bundle signature, and checks current-version behavior. Its HTTP server binds only to loopback. Production transport remains HTTPS.
3. `scripts/prepare-update.sh` reads `SPARKLE_PRIVATE_KEY` from a GitHub Actions secret into a protected temporary file. It verifies that the private key matches `SUPublicEDKey`, signs the DMG and appcast, and verifies the feed signature. No private material is included in the app or artifacts.
4. The workflow uploads the DMG, checksum, signed appcast and notes to the versioned GitHub Release, then publishes the feed to the `updates` branch. Only feed metadata is committed there; historical DMGs remain release assets.

The production feed is `https://raw.githubusercontent.com/Ninnja10563/Render/updates/appcast.xml`. GitHub’s raw-content cache can delay visibility of a new release. Sparkle verifies the feed signature and archive signature before extraction; a plain checksum is not the trust mechanism. `CFBundleVersion` and the display version use the same semantic version, avoiding unrelated workflow-run counters.

The repository’s update signing key is configured as `SPARKLE_PRIVATE_KEY`. Its local backup is outside this checkout at `~/.local/share/render/update-signing/sparkle-ed25519.key`, with owner-only file permissions. Keep an additional secure owner-managed backup. Preserve that key securely: losing it prevents updates to ad-hoc-signed installations. Do not generate a replacement public key for routine releases. Follow Sparkle’s key-rotation procedure when Developer ID signing is available.

## Current limits

The application is ad-hoc signed and not notarized. Sparkle signatures establish continuity with the installed app’s update key; they do not confer Apple Developer ID trust or remove first-install Gatekeeper requirements. Install Render in a writable Applications location before updating. Sparkle reports read-only, permission, network and verification errors; users can retry or keep their current version. Physical-Mac upgrade/relaunch and Gatekeeper qualification remain release-quality work beyond the hosted macOS checks.
