# App Store Assets

App Store Connect submission materials for PingScope.

## Directory Structure

```
AppStoreAssets/
├── Metadata/           # Text content for App Store Connect
│   ├── app-name.txt
│   ├── subtitle.txt
│   ├── description.txt
│   ├── keywords.txt
│   ├── promotional-text.txt
│   ├── copyright.txt
│   ├── support-url.txt
│   └── review-notes.txt
├── Screenshots/        # 2880x1800 screenshots (created in Plan 15-02)
└── README.md          # This file
```

## Metadata Character Limits

| File | Limit | Current |
|------|-------|---------|
| app-name.txt | 30 | 9 |
| subtitle.txt | 30 | 23 |
| description.txt | 4000 | ~1577 |
| keywords.txt | 100 | 95 |
| promotional-text.txt | 170 | 158 |

## Validation

Run automated validation:

```bash
./Scripts/validate-metadata.sh
```

Expected output: All checks pass with ✓ markers.

## Upload Instructions

1. Log in to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to PingScope app listing
3. Copy content from each .txt file to corresponding field
4. Upload screenshots from Screenshots/ directory (Plan 15-02)
5. Submit for review

## Key Messaging

**Differentiators highlighted:**
- Multi-host monitoring with independent intervals
- Automatic gateway detection
- Dual display modes (full + compact)
- Real-time latency graphs
- Smart notification system

**First 250 chars optimize for:**
- Professional positioning
- Core value proposition (menu bar convenience)
- Key features (multi-host, graphs, gateway detection)
- User benefit focus

**Keywords avoid:**
- Trademarked terms ("ping" golf trademark)
- Competitor names
- Generic filler words

## Review Notes Strategy

Explains dual sandbox distribution model clearly to App Review team:
- App Store build: TCP/UDP only (ICMP hidden)
- Developer ID build: TCP/UDP/ICMP available
- Emphasizes feature parity except sandbox-restricted ICMP
- Provides testing instructions for App Review
