# PingScope 0.5.0 Release and Product Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish PingScope 0.5.0 (94) for iOS, macOS TestFlight, GitHub, and keithah.com, with current deterministic screenshots and the same macOS build installed locally.

**Architecture:** Treat PingScope and keithah.com as separate repositories connected by a one-way artifact boundary. PingScope produces reviewed archives, screenshots, a notarized DMG, tag, and release; the Astro site consumes optimized screenshots and publishes only after the artifacts it advertises exist. App Store Connect processing and GitHub Pages deployment are monitored explicitly.

**Tech Stack:** Swift 6, SwiftPM, Xcode 26, TestFlight/App Store Connect, Developer ID/notarytool, Sparkle, GitHub CLI, Astro 4, Node 20, GitHub Pages.

## Global Constraints

- Release identity: `0.5.0`, build `94`, tag `v0.5.0` for iOS and macOS.
- Release from `codex/ios-all-hosts-live-activity`; tag and archives must use the reviewed release commit.
- Public TestFlight URL: `https://testflight.apple.com/join/rvBuNjMz` for Mac and iPhone.
- Do not modify `/Users/keith/src/pingscope/design/`.
- Do not change wire protocols, retention, graph downsampling, or cache fingerprints.
- PingScope commits require `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Never silently replace build 94; stop if App Store Connect reports it already exists.
- Do not publish keithah.com before the advertised TestFlight/GitHub artifacts exist.
- Use sanitized deterministic demo hosts rendered by real production views.
- Preserve unrelated files and user changes in both repositories.

## File map

### PingScope

- Modify: `RELEASE_NOTES.md`
- Modify: `Tests/PingScopeFreshTests/BuildGraph/BuildGraphOptimizationTests.swift`
- Consume: `scripts/validate-ios-simulator-smoke.sh`
- Consume: `scripts/capture-readme-screenshots.sh`
- Consume: `scripts/release-github.sh`
- Consume: `Configuration/ExportOptions-AppStoreUpload.plist`
- Create runtime artifacts only under `.build/release-0.5.0/` and `/private/tmp/artifacts/PingScope-v0.5.0/`.

### keithah.com

- Modify: `src/pages/products/[slug].astro`
- Modify: `src/styles/global.css`
- Modify: `package.json`
- Create: `scripts/validate-pingscope-product-page.mjs`
- Create/replace: `public/products/pingscope/{mac-all-hosts,overlay,ios-signal,ios-ring,ios-widget,ios-live-activity}.png`
- Preserve: `public/products/pingscope/app-icon.png`

---

### Task 1: Release metadata and credential preflight

**Files:**
- Modify: `RELEASE_NOTES.md`
- Test: `Tests/PingScopeFreshTests/BuildGraph/BuildGraphOptimizationTests.swift`

**Interfaces:**
- Consumes: reviewed HEAD and project versions.
- Produces: final notes used by GitHub/Sparkle and a proven release identity.

- [ ] **Step 1: Record immutable preflight state**

```bash
cd /Users/keith/src/pingscope
git status --short
git status --short -- design
git branch --show-current
git rev-parse HEAD
git ls-remote --tags origin refs/tags/v0.5.0
rg -n 'MARKETING_VERSION =|CURRENT_PROJECT_VERSION =' PingScope.xcodeproj/project.pbxproj
gh auth status
xcrun notarytool history --keychain-profile NotarytoolProfile >/dev/null
security find-identity -v -p codesigning
```

Expected: clean tree, empty `design/`, correct branch, no remote v0.5.0, all 14 settings are 0.5.0/94, and GitHub/notary/Apple Distribution/Developer ID credentials work.

- [ ] **Step 2: Write the failing release-note identity test**

Add:

```swift
func testReleaseNotesMatchBuild94AndCurrentCrossPlatformFeatures() throws {
    let root = try repositoryRoot()
    let notes = try String(
        contentsOf: root.appendingPathComponent("RELEASE_NOTES.md"),
        encoding: .utf8
    )
    XCTAssertTrue(notes.contains("Build: 94"))
    XCTAssertTrue(notes.contains("per-host colors"))
    XCTAssertTrue(notes.contains("widget"))
    XCTAssertTrue(notes.contains("Live Activity"))
    XCTAssertFalse(notes.contains("Build: 89"))
    XCTAssertFalse(notes.contains("intentionally not part of this preparation commit"))
}
```

- [ ] **Step 3: Run RED**

```bash
swift test --filter BuildGraphOptimizationTests/testReleaseNotesMatchBuild94AndCurrentCrossPlatformFeatures
```

Expected: behavioral/static contract failure on stale build 89 and missing finished features.

- [ ] **Step 4: Finalize release notes**

Retain the existing performance, All Hosts, Live Activity, sync, and history sections. Add:

```markdown
- Added persistent per-host colors and ordering across Mac, iPhone, widgets, and Live Activities.
- Expanded the iPhone widget to graph and label up to five ordered hosts.
- Added current latency and sparklines to host switching and focused monitoring.
- Fixed default-gateway refresh across network changes and rejected link-local candidates.
- Made connectivity tips optional and off by default.
- Closed host-sync races that could roll back edits or reset active sessions and samples.
- Version: 0.5.0
- Build: 94
```

Remove the preparation-only publication disclaimer.

- [ ] **Step 5: Run GREEN and commit**

```bash
swift test --filter BuildGraphOptimizationTests/testReleaseNotesMatchBuild94AndCurrentCrossPlatformFeatures
git diff --check
git add RELEASE_NOTES.md Tests/PingScopeFreshTests/BuildGraph/BuildGraphOptimizationTests.swift
git commit -m "Finalize PingScope 0.5.0 release notes" \
  -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 2: Capture current production screenshots

**Files:**
- Consume: `scripts/validate-ios-simulator-smoke.sh`
- Consume: `scripts/capture-readme-screenshots.sh`
- Create: `.build/release-0.5.0/screenshots/originals/*.png`
- Create: `/Users/keith/src/keithah.com/public/products/pingscope/*.png`

**Interfaces:**
- Consumes: real production views from 0.5.0 (94).
- Produces: six sanitized, optimized files referenced by Task 3.

- [ ] **Step 1: Define one sanitized fixture**

Use this order everywhere:

```text
Cloudflare DNS   1.1.1.1   teal
Google DNS       8.8.8.8   magenta
Quad9 DNS        9.9.9.9   cyan
Default Gateway  192.0.2.1 lime
```

Use fixed samples spanning 7–38 ms, zero loss, and a fixed relative clock. Never expose a real gateway, SSID, hostname, account, device name, or notification.

- [ ] **Step 2: Build and capture the base iOS and Live Activity surfaces**

```bash
cd /Users/keith/src/pingscope
mkdir -p .build/release-0.5.0/screenshots/originals
PING_SCOPE_CLEAN=1 \
PING_SCOPE_IOS_SMOKE_DERIVED_DATA=.build/release-0.5.0/ios-smoke \
PING_SCOPE_IOS_SMOKE_SCREENSHOT=.build/release-0.5.0/screenshots/originals/ios-signal.png \
PING_SCOPE_IOS_LIVE_ACTIVITY_SCREENSHOT=.build/release-0.5.0/screenshots/originals/ios-live-activity.png \
scripts/validate-ios-simulator-smoke.sh
```

Expected: production app and Live Activity captures exist and smoke validation passes.

- [ ] **Step 3: Seed isolated screenshot state**

Use the simulator data container and a temporary Mac HOME/defaults domain, never the user's real defaults. Save the exact shared-host envelope and widget snapshot fixture at `.build/release-0.5.0/screenshots/fixture.json`, seed the four hosts/samples, then relaunch.

- [ ] **Step 4: Capture every direction-B production surface**

```text
mac-all-hosts.png     windowed All Hosts interface
overlay.png           expanded floating overlay
ios-signal.png        All Hosts Signal
ios-ring.png          All Hosts Ring with identical order/colors
ios-widget.png        medium widget with four lines and key
ios-live-activity.png expanded Lock Screen Live Activity; Dynamic Island when legible
```

Resolve the capture targets explicitly, then capture:

```bash
MAC_WINDOW_ID="$(swift -e 'import CoreGraphics; let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []; let rows = info.compactMap { row -> (Int, Int)? in guard row[kCGWindowOwnerName as String] as? String == "PingScope", let id = row[kCGWindowNumber as String] as? Int, let bounds = row[kCGWindowBounds as String] as? [String: Any], let w = bounds["Width"] as? Int, let h = bounds["Height"] as? Int else { return nil }; return (id, w * h) }.sorted { $0.1 > $1.1 }; print(rows.first!.0)')"
SIM_ID="$(xcrun simctl list devices booted | sed -n 's/.*iPhone 17 Pro (\([-A-F0-9]*\)) (Booted).*/\1/p' | head -n 1)"
screencapture -x -l "${MAC_WINDOW_ID}" .build/release-0.5.0/screenshots/originals/mac-all-hosts.png
xcrun simctl io "${SIM_ID}" screenshot .build/release-0.5.0/screenshots/originals/ios-signal.png
```

Repeat after switching the real production UI to each named surface. Capture Retina originals before cropping/optimization.

- [ ] **Step 5: Inspect and optimize**

```bash
file .build/release-0.5.0/screenshots/originals/*.png
sips -g pixelWidth -g pixelHeight .build/release-0.5.0/screenshots/originals/*.png
```

Visually verify exact host/color parity and privacy. Copy optimized web versions to keithah.com. Keep at least 1200 px on the long edge, except the native Retina overlay, and keep each below 1.5 MB unless visible graph quality requires more.

### Task 3: Build direction B in Astro test-first

**Files:**
- Modify: `/Users/keith/src/keithah.com/package.json`
- Create: `/Users/keith/src/keithah.com/scripts/validate-pingscope-product-page.mjs`
- Modify: `/Users/keith/src/keithah.com/src/pages/products/[slug].astro`
- Modify: `/Users/keith/src/keithah.com/src/styles/global.css`

**Interfaces:**
- Consumes: Task 2 assets and live App Store/TestFlight/GitHub URLs.
- Produces: a contract-tested static product page.

- [ ] **Step 1: Create the built-output validator**

```javascript
import { access, readFile, stat } from 'node:fs/promises';
import { join } from 'node:path';

const root = new URL('..', import.meta.url).pathname;
const html = await readFile(join(root, 'dist/products/pingscope/index.html'), 'utf8');
const required = [
  'PingScope for Mac', 'PingScope for iPhone', 'External TestFlight',
  'https://testflight.apple.com/join/rvBuNjMz',
  'https://apps.apple.com/us/app/pingscope-keep-connected/id6759278369?mt=12',
  'https://github.com/keithah/pingscope', '0.5.0',
];
const assets = [
  'mac-all-hosts.png', 'overlay.png', 'ios-signal.png',
  'ios-ring.png', 'ios-widget.png', 'ios-live-activity.png',
];
for (const value of required) if (!html.includes(value)) throw new Error(`missing: ${value}`);
for (const value of ['iOS is next', 'Coming soon', 'Download 0.3.0']) {
  if (html.includes(value)) throw new Error(`stale: ${value}`);
}
for (const asset of assets) {
  if (!html.includes(`/products/pingscope/${asset}`)) throw new Error(`unreferenced: ${asset}`);
  const path = join(root, 'public/products/pingscope', asset);
  await access(path);
  if ((await stat(path)).size < 10_000) throw new Error(`asset too small: ${asset}`);
}
console.log('PASS: PingScope product page contract');
```

Add:

```json
"validate:pingscope": "npm run build && node scripts/validate-pingscope-product-page.mjs"
```

- [ ] **Step 2: Run RED**

```bash
cd /Users/keith/src/keithah.com
npm run validate:pingscope
```

Expected: FAIL on stale/missing current product content.

- [ ] **Step 3: Implement the approved page hierarchy**

Replace only the `isPingScope` branch with:

```astro
<div class="ps-page">
  <nav class="ps-subnav">brand, Features, Platforms, Download, Support, GitHub</nav>
  <section class="ps-hero">Mac + Signal + Ring hero; App Store/TestFlight/DMG actions</section>
  <section id="features" class="ps-section">three direction-B feature cards</section>
  <section id="platforms" class="ps-section">equal Mac and iPhone cards</section>
  <section id="ambient" class="ps-section">widget and Live Activity proof</section>
  <section id="download" class="ps-section">App Store/TestFlight/dynamic GitHub release</section>
  <section id="support" class="ps-section">existing support form</section>
</div>
```

Reference all six exact asset filenames. Give every image meaningful alt text. Use the public TestFlight URL for both platform buttons. Preserve GitHub latest-release loading and change the static fallback to `v0.5.0` / `PingScope-v0.5.0.dmg`.

- [ ] **Step 4: Implement scoped direction-B styles**

Within the existing `ps-` namespace implement: `#080a0b` graph-grid background, warm off-white headings, vivid PingScope-green accents, three-image hero, three compact feature cards, equal Mac/iPhone cards, two-column ambient section, visible focus states, reduced-motion-safe transitions, and a single-column layout below 900 px with no overflow at 320 px. Do not alter unrelated pages.

- [ ] **Step 5: Run GREEN and commit keithah.com locally**

```bash
npm run validate:pingscope
git diff --check
git add package.json scripts/validate-pingscope-product-page.mjs \
  src/pages/products/'[slug].astro' src/styles/global.css public/products/pingscope
git commit -m "Refresh the PingScope product page"
```

Do not push yet.

### Task 4: Browser and accessibility verification

**Files:**
- Verify: `/Users/keith/src/keithah.com/dist/products/pingscope/index.html`

**Interfaces:**
- Consumes: Task 3.
- Produces: desktop/mobile approval before publication.

- [ ] **Step 1: Start production preview**

```bash
cd /Users/keith/src/keithah.com
npm run build
npm run preview -- --host 127.0.0.1
```

- [ ] **Step 2: Inspect at 1440×1000, 1024×768, 390×844, and 320×568**

Verify hero hierarchy, crisp unclipped imagery, correct reading order, stacked mobile cards, no horizontal scroll, legible ambient surfaces, and visible actions.

- [ ] **Step 3: Inspect accessibility and outbound links**

Confirm one h1, ordered h2 sections, named navigation/form controls, useful alt text, keyboard focus, reduced-motion behavior, and no empty links. Open App Store, TestFlight, GitHub repository, support, and dynamic release destinations.

- [ ] **Step 4: Re-run the gate**

```bash
npm run validate:pingscope
git status --short
```

Expected: PASS and clean committed site tree.

### Task 5: Final PingScope verification and current local Mac install

**Files:**
- Produce: `.build/release-0.5.0/local/PingScope.app`
- Replace recoverably: `/Applications/PingScope.app`

**Interfaces:**
- Consumes: final release commit.
- Produces: release gate evidence and current Mac app for user review.

- [ ] **Step 1: Run final gates serially**

```bash
cd /Users/keith/src/pingscope
swift build
swift test
xcodebuild -project PingScope.xcodeproj -scheme PingScope-iOS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/release-0.5.0/verify-ios CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PingScope.xcodeproj -scheme PingScope-DeveloperID \
  -destination 'generic/platform=macOS' -jobs 1 \
  -derivedDataPath .build/release-0.5.0/verify-mac build
PATH="$(brew --prefix ripgrep)/bin:$PATH" scripts/validate-ios.sh
scripts/validate-app-smoke.sh
git diff --check
git status --short -- design
```

Expected: at least 948 tests pass; both builds/scripts pass; `design/` remains untouched.

- [ ] **Step 2: Build and verify local bundle**

```bash
scripts/build-xcode-app-bundle.sh release .build/release-0.5.0/local developer-id
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  .build/release-0.5.0/local/PingScope.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  .build/release-0.5.0/local/PingScope.app/Contents/Info.plist
```

Expected: 0.5.0 and 94.

- [ ] **Step 3: Replace and launch recoverably**

```bash
osascript -e 'tell application "PingScope" to quit' || true
ditto /Applications/PingScope.app /private/tmp/PingScope-before-0.5.0.app
ditto .build/release-0.5.0/local/PingScope.app /Applications/PingScope.app
open /Applications/PingScope.app
```

Confirm 0.5.0 (94), current All Hosts/colors/order UI, and keep the backup until user approval.

### Task 6: Push source and upload both TestFlight archives

**Files:**
- Produce: `.build/release-0.5.0/archives/PingScope-iOS-0.5.0-94.xcarchive`
- Produce: `.build/release-0.5.0/archives/PingScope-macOS-0.5.0-94.xcarchive`

**Interfaces:**
- Consumes: clean verified commit.
- Produces: remote source branch and App Store Connect build 94 on both platforms.

- [ ] **Step 1: Push without force and verify IDs**

```bash
git status --short
git push -u origin codex/ios-all-hosts-live-activity
git rev-parse HEAD
git ls-remote origin refs/heads/codex/ios-all-hosts-live-activity
```

- [ ] **Step 2: Archive iOS**

```bash
mkdir -p .build/release-0.5.0/archives .build/release-0.5.0/exports/ios
xcodebuild -project PingScope.xcodeproj -scheme PingScope-iOS \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath .build/release-0.5.0/archives/PingScope-iOS-0.5.0-94.xcarchive archive
```

- [ ] **Step 3: Archive macOS serially**

```bash
xcodebuild -project PingScope.xcodeproj -scheme PingScope-AppStore \
  -configuration Release -destination 'generic/platform=macOS' -jobs 1 \
  -archivePath .build/release-0.5.0/archives/PingScope-macOS-0.5.0-94.xcarchive archive
```

- [ ] **Step 4: Validate signed archive identity**

Inspect archive Info.plists and run `codesign -d --entitlements :-` on apps/extensions. Confirm Team ID `6R7S5GA944`, correct bundle IDs, 0.5.0/94, canonical app group, and `iCloud.com.hadm.PingScope`; ensure App Store archives do not contain Developer ID/Sparkle-only entitlements.

- [ ] **Step 5: Export/upload iOS**

```bash
xcodebuild -exportArchive \
  -archivePath .build/release-0.5.0/archives/PingScope-iOS-0.5.0-94.xcarchive \
  -exportOptionsPlist Configuration/ExportOptions-AppStoreUpload.plist \
  -exportPath .build/release-0.5.0/exports/ios
```

- [ ] **Step 6: Export/upload macOS**

```bash
mkdir -p .build/release-0.5.0/exports/macos
xcodebuild -exportArchive \
  -archivePath .build/release-0.5.0/archives/PingScope-macOS-0.5.0-94.xcarchive \
  -exportOptionsPlist Configuration/ExportOptions-AppStoreUpload.plist \
  -exportPath .build/release-0.5.0/exports/macos
```

If either reports build 94 already exists, stop. Otherwise record delivery IDs.

- [ ] **Step 7: Process and enable external testing**

In App Store Connect, wait for both 0.5.0 (94) builds to leave Processing, complete established export-compliance answers, add both to the existing external group behind `rvBuNjMz`, and submit Beta App Review when required. Report pending review honestly; never substitute another build.

### Task 7: Publish signed/notarized GitHub release

**Files:**
- Consume: `RELEASE_NOTES.md`
- Produce: `/private/tmp/artifacts/PingScope-v0.5.0/PingScope-v0.5.0.dmg`
- Publish: `v0.5.0`

**Interfaces:**
- Consumes: pushed release commit and valid Developer ID CloudKit profile.
- Produces: notarized DMG, checksums, appcast, tag, release, and PingScope gh-pages.

- [ ] **Step 1: Resolve an explicit valid Developer ID profile path**

Use `scripts/lib/developer-id-profile.sh` to select a non-expired `com.hadm.PingScope` profile carrying the canonical app group and `iCloud.com.hadm.PingScope`. Export it as `PING_SCOPE_DEVELOPER_ID_PROFILE`; do not use an unresolved glob.

- [ ] **Step 2: Run dry-run**

```bash
scripts/release-github.sh --version 0.5.0 \
  --release-notes RELEASE_NOTES.md --dry-run \
  --provisioning-profile "${PING_SCOPE_DEVELOPER_ID_PROFILE}"
```

Expected: signed/notarized/stapled DMG, appcast, and checksums without tag/release publication.

- [ ] **Step 3: Verify dry-run artifacts**

```bash
spctl --assess --type open --context context:primary-signature -vv \
  /private/tmp/artifacts/PingScope-v0.5.0/PingScope-v0.5.0.dmg
xcrun stapler validate /private/tmp/artifacts/PingScope-v0.5.0/PingScope-v0.5.0.dmg
scripts/validate-sparkle-feed.sh 0.5.0
```

Mount read-only; verify contained app 0.5.0 (94), Developer ID signature, CloudKit/app-group entitlements, and Gatekeeper launch.

- [ ] **Step 4: Publish release**

```bash
scripts/release-github.sh --version 0.5.0 \
  --release-notes RELEASE_NOTES.md \
  --provisioning-profile "${PING_SCOPE_DEVELOPER_ID_PROFILE}"
```

- [ ] **Step 5: Verify publication**

```bash
git rev-parse HEAD
git rev-list -n 1 v0.5.0
git ls-remote origin refs/tags/v0.5.0
gh release view v0.5.0 --json tagName,url,assets,publishedAt
curl -fsSL https://keithah.github.io/pingscope/appcast.xml | rg '0.5.0|PingScope-v0.5.0'
```

Expected: tag/local/remote commit IDs match and assets resolve.

### Task 8: Publish and verify keithah.com

**Files:**
- Publish: `/Users/keith/src/keithah.com` current `main`.

**Interfaces:**
- Consumes: live TestFlight URL/build membership and live v0.5.0 GitHub release.
- Produces: `https://keithah.com/products/pingscope`.

- [ ] **Step 1: Run final site gate**

```bash
cd /Users/keith/src/keithah.com
npm ci
npm run validate:pingscope
git diff --check
git status --short
```

- [ ] **Step 2: Push main and verify IDs**

```bash
git push origin main
git rev-parse HEAD
git ls-remote origin refs/heads/main
```

- [ ] **Step 3: Monitor Pages**

```bash
gh run list --repo keithah/keithah.com --workflow deploy.yml --limit 5
RUN_ID="$(gh run list --repo keithah/keithah.com --workflow deploy.yml --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch --repo keithah/keithah.com --exit-status "${RUN_ID}"
```

- [ ] **Step 4: Validate production**

Open `https://keithah.com/products/pingscope` at desktop/mobile widths. Verify six current screenshots, no coming-soon copy, v0.5.0 download, App Store, Mac/iPhone external TestFlight, support, and GitHub; confirm no 404, overflow, mixed content, or accessibility regression.

- [ ] **Step 5: Final report and cleanup boundary**

```bash
git -C /Users/keith/src/pingscope status --short
git -C /Users/keith/src/pingscope status --short -- design
git -C /Users/keith/src/keithah.com status --short
```

Report commits, tag, GitHub release URL, checksums, notarization, TestFlight status per platform, Pages run/live URL, local app version, and verification totals. Delete `/private/tmp/PingScope-before-0.5.0.app` only after the user confirms the current Mac app works.
