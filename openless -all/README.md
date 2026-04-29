# OpenLess All-Platform

This is the current cross-platform OpenLess workspace.

## App Directory

The runnable Tauri app lives in `app/`.

```bash
cd app
npm ci
npm run tauri dev
```

## macOS Build

Use the project build script instead of calling `tauri build` directly:

```bash
cd app
INSTALL=0 ./scripts/build-mac.sh
```

Generated macOS artifacts:

- `app/src-tauri/target/release/bundle/macos/OpenLess.app`
- `app/src-tauri/target/release/bundle/dmg/OpenLess_1.1.0_aarch64.dmg`

For local install during development:

```bash
cd app
./scripts/build-mac.sh
```

## Release Signing

Tagged releases (`v*-tauri`) must be Developer ID signed and notarized so users can download and open the macOS app without manually removing quarantine attributes.

Required GitHub secrets:

- `APPLE_CERTIFICATE`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_ID`
- `APPLE_PASSWORD`
- `APPLE_TEAM_ID`

Optional:

- `APPLE_PROVIDER_SHORT_NAME`
- `KEYCHAIN_PASSWORD`

Manual workflow runs can still produce ad-hoc signed test builds, but tagged macOS releases fail if signing/notarization secrets are missing.

## Ignored Local Output

The following are intentionally local-only:

- `app/node_modules/`
- `app/dist/`
- `app/src-tauri/target/`
- `app/src-tauri/gen/`
- `.DS_Store`
