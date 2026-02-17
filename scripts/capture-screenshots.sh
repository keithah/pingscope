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

screenshots=(
    "01-menu-bar-full-interface"
    "02-multi-host-graph"
    "03-settings-panel"
    "04-ping-history-stats"
    "05-compact-mode"
)

for name in "${screenshots[@]}"; do
    echo "Capturing: $name"
    echo "Click the window to capture (or Esc to skip)..."

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
