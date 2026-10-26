# Release engineering

## Scope and ownership

The maintainer owns release builds. Scripts write only to this checkout's ignored `build/`, `dist/`, generated Xcode project and package caches, plus requested screenshots in `Docs/images/`. They never launch the personal board, install over an existing app, edit user data or provision new certificates.

Supply the signing identity and notarization profile through environment variables and the existing macOS Keychain. Do not commit credentials, environment files, certificates or private keys. Signer identity and Team ID are public signature metadata.

## Validate

Use Xcode 26 or later, XcodeGen and Python 3 on macOS:

```bash
make test
make release-build
python3 scripts/test-agent.py
make screenshots
git add .
make audit
```

Review staged files, screenshots and source changes manually. Documentation and comments are English except `README.zh-CN.md`; localized interface strings and partition values retain their languages. Never stage a personal board or historical import.

## Build and package

`make release-build` creates a universal arm64/x86_64 Release app and `Contents/Helpers/manuscript-matrix-agent`. It excludes development debug dylibs, maps checkout paths to a neutral source prefix and audits the bundle. No signing credentials are needed for this step.

Use an existing Developer ID Application identity and notarytool Keychain profile:

```bash
export MM_SIGN_IDENTITY='Developer ID Application: YOUR EXISTING IDENTITY'
export MM_NOTARY_PROFILE='YOUR EXISTING KEYCHAIN PROFILE'
bash scripts/package-release.sh --skip-build
```

Omit `--skip-build` to build first. The script signs nested code before the app with hardened runtime and secure timestamps. It submits a temporary ZIP, requires an Accepted notarization result, staples the ticket, and runs Gatekeeper assessment. It packages the stapled app, extracts the final ZIP into a disposable directory, verifies the extracted signature and ticket, audits that exact payload, and generates SHA-256 checksums.

Outputs are `dist/Manuscript-Matrix-<version>-universal.zip` and its `.sha256`. The ZIP contains only the app, including the MCP helper and MIT license. Never publish DerivedData, debug symbols, build logs or notarization logs. Apple silicon runtime checks and Intel cross-compilation are separate checks; do not claim Intel runtime testing unless performed.

## Screenshots

`make screenshots` invokes the executable with `--export-demo-screenshot`, once per language. It renders the actual SwiftUI view with an in-memory board in an offscreen hosting view. It does not capture the desktop. Command-line preference overrides leave saved personal preferences unchanged. All example venues, manuscripts and metrics are fictional. Review the PNGs before committing them.

## Publish

Update the version/build in `project.yml`, MCP version, `CHANGELOG.md` and release notes together. The first public version is `v0.9.0`. Use GitHub's noreply commit email. Initialize new Git history from reviewed source for the first public release; never push old private history.

After source and payload review, push the release commit, create its version tag, and attach only the verified ZIP and checksum to GitHub Releases. Source-only CI needs no signing secrets; signing and notarization remain local.

## Cleanup

An EXIT trap removes the package script's temporary submission ZIP, extraction directory and notarization response on success or failure. When debugging, inspect errors before removing remaining build logs. Stop task-owned processes before cleanup. Source, screenshots and the verified release archive/checksum are durable outputs.

After verification, remove only this checkout's generated outputs if no longer needed:

```bash
rm -rf build DerivedData .build Packages/ManuscriptKit/.build ManuscriptMatrix.xcodeproj
```

Keep `dist/` for the verified release, or remove it after confirming the uploaded checksum. These paths do not include Application Support, the Keychain or other projects. No ongoing cleanup job, listener or watcher is installed.
