# External TestFlight CTA Design

## Goal

Make it unmistakable that the product-page beta links enroll external testers on both supported platforms.

## Behavior

- Keep the existing public TestFlight URL: `https://testflight.apple.com/join/rvBuNjMz`.
- Label the hero action **Join External TestFlight**.
- Label the platform actions **External TestFlight — Mac** and **External TestFlight — iPhone**.
- Preserve the separate Mac App Store and Developer ID download actions.
- Preserve the existing platform screenshots, layout, and release-data behavior.

## Publication

Validate the static HTML, desktop and mobile rendering, outbound TestFlight URL, and absence of horizontal overflow. Commit only the site-copy change, push the current branch, then copy `deploy/site` onto the existing `gh-pages` branch without deleting unrelated release artifacts such as the Sparkle appcast or DMGs.

## Non-goals

- Do not change TestFlight groups, builds, app binaries, app versions, or release artifacts.
- Do not touch `design/` or the three existing uncommitted peer-latency files.
