#!/bin/bash
# Build Flutter APK
# Run from project root directory

set -e

echo "=== Flutter APK Build ==="
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

# Build APK
echo ">>> Building APK..."
flutter build apk --release

# Show output
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
if [ -f "$APK_PATH" ]; then
    echo ""
    echo "=== BUILD SUCCESS ==="
    echo "APK Location: $APK_PATH"
    echo "Size: $(du -h "$APK_PATH" | cut -f1)"
else
    echo "ERROR: APK not found at expected location"
    exit 1
fi
