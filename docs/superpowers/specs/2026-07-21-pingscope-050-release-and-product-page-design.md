# PingScope 0.5.0 Release and Product Page Design

## Goal

Ship the reviewed PingScope tree as version 0.5.0, build 94, on iOS and macOS; publish a signed and notarized GitHub release; refresh `keithah.com/products/pingscope` with current product imagery and public beta links; and install the same macOS build locally for manual review.

## Release identity

- Marketing version: `0.5.0`
- Build number: `94`
- Git tag and GitHub release: `v0.5.0`
- iOS TestFlight build: `0.5.0 (94)`
- macOS TestFlight build: `0.5.0 (94)`
- Developer ID package: `PingScope-v0.5.0.dmg`
- Public TestFlight URL: `https://testflight.apple.com/join/rvBuNjMz`

No version or build-number change is part of this release. The release must be produced from the reviewed commit on `codex/ios-all-hosts-live-activity` and the tag must resolve to that exact commit.

## Product-page direction

Use direction B from the approved visual comparison: a dark, graph-paper product page with a balanced Mac/iPhone story.

### Hero

- Present PingScope as a native graph-first latency monitor for macOS and iPhone.
- Show three fresh production captures: Mac All Hosts, iPhone Signal, and iPhone Ring.
- Lead with Mac App Store, public TestFlight, Developer ID download, support, and GitHub actions.
- Remove all “iOS coming soon” language.

### Feature and platform sections

- Explain graph-first monitoring, stable host identity colors, and local/upstream/destination context.
- Give macOS and iPhone equal platform cards.
- The Mac card shows the current All Hosts popover and floating overlay.
- The iPhone card shows Signal and Ring views.
- A supporting ambient section shows the current multi-host widget and Live Activity/Dynamic Island behavior without competing with the hero.
- Describe connectivity tips as optional and off by default.

### Download and beta actions

- Keep the Mac App Store as the simplest macOS install path.
- Link both Mac and iPhone beta actions to the public external TestFlight URL.
- Load the latest Developer ID release dynamically from GitHub while keeping `v0.5.0` as the static fallback.
- Preserve the existing support form and repository link.

## Screenshot production

All new screenshots use deterministic demo data rendered by real production views from 0.5.0 (94). They must not expose personal SSIDs, public IP addresses, hostnames, account information, or notifications.

Capture and publish:

1. Mac All Hosts popover with three to five color-distinct hosts and populated latency series.
2. Mac floating overlay with a populated graph.
3. iPhone All Hosts Signal view with color-matched graph, host rows, and latencies.
4. iPhone All Hosts Ring view with the same host identities.
5. Medium iPhone widget with three to five colored series and its key.
6. Lock Screen Live Activity or an equivalent production preview showing multiple host series; include Dynamic Island only when the capture is legible.

Capture originals at Retina resolution. Store optimized web copies under the `keithah.com` PingScope public asset directory. Preserve readable UI text and avoid lossy compression artifacts around graphs.

## Repository boundaries

### PingScope

- Source, tests, release notes, tag, GitHub release, TestFlight archives, notarized DMG, and local macOS app installation.
- Do not modify `design/`.
- Push the current feature branch before tagging. Do not rewrite published history.

### keithah.com

- Astro product-page markup, PingScope public assets, and page-specific styling only.
- Commit and push `main`; the existing GitHub Pages workflow performs production deployment.
- Do not copy the separate `deploy/site` static page over the Astro site.

## Release sequence

1. Reconfirm clean worktrees, versions, tag availability, signing identities, provisioning, App Store Connect credentials, and GitHub authentication.
2. Produce deterministic screenshots from the reviewed build and update the Astro page locally.
3. Validate the site at desktop and mobile widths, build it with Astro, and verify outbound links and accessible image text.
4. Re-run the PingScope release gates and inspect signed entitlements.
5. Push the reviewed PingScope branch.
6. Create iOS and macOS distribution archives from the same commit and upload build 94 to App Store Connect.
7. Wait for processing. Add both builds to the external testing group when eligible; report any Beta App Review delay rather than substituting another build.
8. Build, sign, notarize, staple, and verify the Developer ID DMG; create and push tag `v0.5.0`; create the GitHub release with release notes and Sparkle artifacts.
9. Install the verified macOS app into `/Applications`, launch it, and confirm 0.5.0 (94).
10. Commit and push `keithah.com/main` only after the advertised artifacts and public links exist. Wait for Pages deployment and validate the live product URL.

The GitHub release script may update PingScope's own `gh-pages` appcast/download site. That is separate from the Astro `keithah.com` deployment and must not overwrite either site's unrelated files.

## Verification

### PingScope

- `swift build`
- `swift test`
- iOS Simulator build
- serial Developer ID macOS build
- `scripts/validate-ios.sh`
- `scripts/validate-app-smoke.sh`
- release validation, signature, notarization, staple, Gatekeeper, appcast, archive, and entitlement checks
- physical iPhone install already completed for the reviewed commit; distribution archives must still be validated independently

### Product page

- `npm run build`
- desktop and mobile browser inspection
- no horizontal overflow
- useful alternative text for every screenshot
- correct App Store, TestFlight, GitHub release, support, and repository URLs
- live production verification after GitHub Pages completes

## Failure handling

- Do not publish a tag or release when signing, notarization, archive validation, or required tests fail.
- Do not bump or replace build 94 silently. If App Store Connect rejects it as already used, stop and request approval for a new build number.
- If Apple processing or Beta App Review is pending, publish only the artifacts that are truly available and report the pending state explicitly.
- If the website deployment fails, keep the app release intact, fix the site deployment separately, and do not rewrite the release tag.

## Success criteria

- GitHub and both local repositories are clean at published commits.
- `v0.5.0` resolves to the reviewed PingScope release commit.
- The signed/notarized DMG and both TestFlight builds identify themselves as 0.5.0 (94).
- `/Applications/PingScope.app` is the same current build and launches successfully.
- `https://keithah.com/products/pingscope` shows current Mac/iPhone screenshots, current download information, and functioning public TestFlight links.
- No `design/` files are changed.
