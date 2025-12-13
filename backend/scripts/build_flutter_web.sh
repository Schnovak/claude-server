#!/bin/bash
# Build Flutter Web
# Run from project root directory

set -e

echo "=== Flutter Web Build ==="
echo "Project: $(pwd)"
echo "Date: $(date)"
echo ""

# Check if it's a Flutter project
if [ ! -f "pubspec.yaml" ]; then
    echo "ERROR: Not a Flutter project (pubspec.yaml not found)"
    exit 1
fi

# Get dependencies
echo ">>> Getting dependencies..."
flutter pub get

# Build web
echo ">>> Building Web..."
flutter build web --release

# Show output
WEB_PATH="build/web"
if [ -d "$WEB_PATH" ]; then
    echo ""
    echo "=== BUILD SUCCESS ==="
    echo "Web Build Location: $WEB_PATH"
    echo "Files: $(find "$WEB_PATH" -type f | wc -l)"
    echo "Size: $(du -sh "$WEB_PATH" | cut -f1)"
else
    echo "ERROR: Web build not found at expected location"
    exit 1
fi
