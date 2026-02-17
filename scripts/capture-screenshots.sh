#!/bin/bash
# App Store Screenshot Capture Tool
# Source: Phase 15 Research - macOS screencapture automation
# https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/

OUTPUT_DIR="AppStoreAssets/Screenshots"
REQUIRED_WIDTH=2880
REQUIRED_HEIGHT=1800

mkdir -p "$OUTPUT_DIR"

echo "App Store Screenshot Capture Tool"
echo "=================================="
echo "Required resolution: ${REQUIRED_WIDTH}x${REQUIRED_HEIGHT} (16:10 aspect ratio)"
echo ""
echo "Instructions:"
echo "1. Set display to 'Default for display' resolution"
echo "2. Position app window center-screen"
echo "3. Follow prompts to capture each screenshot"
echo ""

# Screenshot descriptions and setup instructions
declare -A descriptions
descriptions["01-menu-bar-full-interface"]="Menu bar icon + full interface|Open full mode (click menu bar icon), position center-screen, show menu bar with PingScope icon visible"
descriptions["02-multi-host-graph"]="Multi-host tabs + real-time graph|Switch to host with populated graph, ensure visible latency curve, show multiple host tabs"
descriptions["03-settings-panel"]="Settings panel|Open Settings (Cmd+,), show Hosts or Notifications tab, ensure content is readable"
descriptions["04-ping-history-stats"]="Ping history with statistics|Show full mode, scroll history to show multiple entries with Success/Failed states"
descriptions["05-compact-mode"]="Compact mode view|Toggle to compact mode (Display > Compact Mode), position center-screen, show latency and status"

screenshots=(
    "01-menu-bar-full-interface"
    "02-multi-host-graph"
    "03-settings-panel"
    "04-ping-history-stats"
    "05-compact-mode"
)

for name in "${screenshots[@]}"; do
    IFS='|' read -r title instructions <<< "${descriptions[$name]}"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Screenshot: $title"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Setup: $instructions"
    echo ""
    read -p "Press Enter when ready to capture (or Ctrl+C to abort)..."

    # -o: opens captured image in Preview for review
    # -w: captures window (interactive selection)
    screencapture -o -w "$OUTPUT_DIR/${name}.png"

    if [ -f "$OUTPUT_DIR/${name}.png" ]; then
        # Verify dimensions
        width=$(sips -g pixelWidth "$OUTPUT_DIR/${name}.png" | awk '/pixelWidth:/ {print $2}')
        height=$(sips -g pixelHeight "$OUTPUT_DIR/${name}.png" | awk '/pixelHeight:/ {print $2}')

        if [ "$width" -eq "$REQUIRED_WIDTH" ] && [ "$height" -eq "$REQUIRED_HEIGHT" ]; then
            echo "✓ Dimensions verified: ${width}x${height}"
        else
            echo "⚠ WARNING: Dimensions ${width}x${height} don't match required ${REQUIRED_WIDTH}x${REQUIRED_HEIGHT}"
            echo "  Attempting resize..."
            sips -z "$REQUIRED_HEIGHT" "$REQUIRED_WIDTH" "$OUTPUT_DIR/${name}.png"
            echo "✓ Resized to ${REQUIRED_WIDTH}x${REQUIRED_HEIGHT}"
        fi
        echo ""
        echo "Screenshot opened in Preview for review."
        echo "Close Preview or press Enter to continue to next screenshot..."
        read
    else
        echo "⚠ Skipped"
    fi
    echo ""
done

echo "Screenshot capture complete!"
echo "Review files in: $OUTPUT_DIR"
echo ""
echo "Next steps:"
echo "1. Verify screenshots look professional and clear"
echo "2. Check that all required UI elements are visible"
echo "3. Re-capture any screenshots if needed (script is rerunnable)"
