#!/bin/bash
# App Store Metadata Validation Script
# Source: Phase 15 Research - metadata character limit validation

METADATA_DIR="AppStoreAssets/Metadata"

validate_length() {
    local file=$1
    local limit=$2
    local label=$3

    if [ ! -f "$file" ]; then
        echo "⚠ $label: File not found ($file)"
        return 1
    fi

    local count=$(echo -n "$(cat "$file")" | wc -c | tr -d ' ')

    if [ "$count" -gt "$limit" ]; then
        echo "✗ $label: $count chars (exceeds $limit limit)"
        return 1
    else
        echo "✓ $label: $count/$limit chars"
        return 0
    fi
}

echo "App Store Metadata Validation"
echo "=============================="
echo ""

all_valid=true

validate_length "$METADATA_DIR/app-name.txt" 30 "App Name" || all_valid=false
validate_length "$METADATA_DIR/subtitle.txt" 30 "Subtitle" || all_valid=false
validate_length "$METADATA_DIR/description.txt" 4000 "Description" || all_valid=false
validate_length "$METADATA_DIR/keywords.txt" 100 "Keywords" || all_valid=false
validate_length "$METADATA_DIR/promotional-text.txt" 170 "Promotional Text" || all_valid=false

echo ""
echo "First 250 Characters (Above the Fold Preview):"
echo "=============================================="
echo ""
head -c 250 "$METADATA_DIR/description.txt"
echo ""
echo ""
echo "=============================================="

char_count=$(head -c 250 "$METADATA_DIR/description.txt" | wc -c | tr -d ' ')
echo "Character count: $char_count/250"

if [ "$char_count" -lt 200 ]; then
    echo "⚠ WARNING: Below recommended 200-250 character range"
fi

echo ""
echo "Keyword Analysis:"
if [ -f "$METADATA_DIR/keywords.txt" ]; then
    keyword_count=$(grep -o ',' "$METADATA_DIR/keywords.txt" | wc -l | tr -d ' ')
    keyword_count=$((keyword_count + 1))
    echo "  Number of keywords: $keyword_count"
    echo "  Content: $(cat "$METADATA_DIR/keywords.txt")"
fi

echo ""
if [ "$all_valid" = true ]; then
    echo "✓ All metadata validations passed"
    exit 0
else
    echo "✗ Validation failed - fix issues before upload"
    exit 1
fi
