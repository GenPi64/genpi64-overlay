#!/usr/bin/env bash
# Script to regenerate manifests for modified ebuilds
# Useful for PRs when ebuilds have been updated

set -e

echo "Finding modified ebuild files..."

# Get list of modified .ebuild files in git
MODIFIED_EBUILDS=$(git diff --name-only HEAD | grep '\.ebuild$' || true)

if [ -z "$MODIFIED_EBUILDS" ]; then
    echo "No modified ebuild files found in current changes."
    echo "Checking for new/untracked ebuild files..."
    MODIFIED_EBUILDS=$(git ls-files --others --exclude-standard | grep '\.ebuild$' || true)
fi

if [ -z "$MODIFIED_EBUILDS" ]; then
    echo "No ebuild files to process."
    exit 0
fi

echo "Found ebuild files:"
echo "$MODIFIED_EBUILDS" | sed 's/^/  - /'
echo ""

# Process each ebuild
for EBUILD in $MODIFIED_EBUILDS; do
    if [ ! -f "$EBUILD" ]; then
        echo "⚠ Skipping $EBUILD (file not found)"
        continue
    fi

    echo "Processing: $EBUILD"

    # Get the directory containing the ebuild
    EBUILD_DIR=$(dirname "$EBUILD")

    # Run ebuild manifest
    if ebuild "$EBUILD" manifest; then
        echo "✓ Manifest generated for $EBUILD"
    else
        echo "✗ Failed to generate manifest for $EBUILD"
        exit 1
    fi

    echo ""
done

echo "✓ All manifests regenerated successfully"
echo ""

# Check if Manifest files were modified
MODIFIED_MANIFESTS=$(git diff --name-only | grep 'Manifest$' || true)
if [ -n "$MODIFIED_MANIFESTS" ]; then
    echo "Modified Manifest files:"
    echo "$MODIFIED_MANIFESTS" | sed 's/^/  - /'
    echo ""
    echo "Run 'git add' to stage these changes for commit."
fi
