# External TestFlight CTA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish explicit external TestFlight calls to action on the PingScope product page, then install the freshly built app on the connected iPhone.

**Architecture:** Keep the existing shared public TestFlight URL and change only its visible CTA copy in the static site. Validate the rendered site at desktop and mobile widths, publish `deploy/site` into the existing `gh-pages` branch while preserving other release files, then perform a signed Debug device build from the current tree and install it with `devicectl`.

**Tech Stack:** Static HTML/CSS, Git/GitHub Pages, Xcode, `xcrun devicectl`, browser automation.

## Global Constraints

- Use `https://testflight.apple.com/join/rvBuNjMz` for both Mac and iPhone external testing.
- Do not alter app versions, TestFlight groups/builds, app binaries, or release artifacts as part of the site publication.
- Preserve the three existing uncommitted peer-latency files.
- Do not touch `design/`.

---

### Task 1: Update and validate external beta CTAs

**Files:**
- Modify: `deploy/site/index.html`

**Interfaces:**
- Consumes: the existing three anchors pointing to the shared public TestFlight URL.
- Produces: hero text `Join External TestFlight`, Mac text `External TestFlight — Mac`, and iPhone text `External TestFlight — iPhone`.

- [ ] Confirm the current HTML fails a content assertion for the three approved labels.
- [ ] Change only the three visible anchor labels.
- [ ] Verify exactly three anchors retain the approved URL and approved labels.
- [ ] Render at desktop and 390-pixel mobile widths, verify all images load and no horizontal overflow exists.
- [ ] Commit `deploy/site/index.html` with the required Claude co-author trailer.

### Task 2: Publish the static site

**Files:**
- Publish: `deploy/site/**` to the existing remote `gh-pages` branch.

**Interfaces:**
- Consumes: committed static-site files.
- Produces: updated GitHub Pages content without deleting `appcast.xml`, DMGs, or unrelated assets.

- [ ] Push the current source branch.
- [ ] Clone `gh-pages` into a temporary directory and merge-copy `deploy/site` into it.
- [ ] Review the staged Pages diff, commit only changed site files, and push `gh-pages`.
- [ ] Open the production Pages URL and verify the three external TestFlight CTAs and platform screenshots.

### Task 3: Install the current build on the connected iPhone

**Files:**
- Build from the current repository tree; do not mutate source or version settings.

**Interfaces:**
- Consumes: scheme `PingScope-iOS` and connected device `D7CC0DBD-509D-5937-A38E-B9142C6CCA0D`.
- Produces: a signed Debug `PingScope.app` installed directly on the device.

- [ ] Build `PingScope-iOS` for the connected device into a dedicated DerivedData directory.
- [ ] Install the resulting app using `xcrun devicectl device install app`.
- [ ] Launch `com.hadm.PingScope`; if the phone is locked, report that install succeeded and ask the user to unlock/open it.
- [ ] Confirm `git diff --check`, `design/` untouched, and the three peer-latency files remain present.
