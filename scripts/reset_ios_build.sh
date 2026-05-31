#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "[1/6] Stopping stale iOS build processes..."
pkill -f "xcodebuild .*Runner.xcworkspace" 2>/dev/null || true
pkill -f "xcodebuild -workspace Runner.xcworkspace -scheme Runner" 2>/dev/null || true
pkill -f "flutter_tools.snapshot assemble.*mi_app/build/ios" 2>/dev/null || true
pkill -f "flutter_tools.snapshot.*assemble.*${ROOT_DIR}" 2>/dev/null || true
pkill -f "xcode_backend.sh build" 2>/dev/null || true
pkill -f "xcode_backend.dart build ios" 2>/dev/null || true
pkill -f "Runner.build/Script-9740EEB61CF901F6004384FC.sh" 2>/dev/null || true
pkill -f "flutter run -v -d" 2>/dev/null || true

# Last-resort cleanup for any lingering Flutter iOS build workers.
pkill -9 -f "flutter_tools.snapshot assemble" 2>/dev/null || true
pkill -9 -f "xcode_backend.sh build" 2>/dev/null || true
pkill -9 -f "xcode_backend.dart build ios" 2>/dev/null || true
pkill -9 -f "xcodebuild .*Runner.xcworkspace" 2>/dev/null || true

echo "[2/6] Removing Runner DerivedData..."
rm -rf "$HOME/Library/Developer/Xcode/DerivedData/Runner-"*

echo "[3/7] Removing Xcode module cache..."
rm -rf "$HOME/Library/Developer/Xcode/DerivedData/ModuleCache.noindex"

echo "[4/7] Removing iOS build output..."
rm -rf "$ROOT_DIR/build/ios"

echo "[5/7] Cleaning Flutter artifacts..."
cd "$ROOT_DIR"
flutter clean

echo "[6/7] Getting Dart/Flutter dependencies..."
flutter pub get

echo "[7/7] Refreshing CocoaPods..."
cd "$ROOT_DIR/ios"
pod install

echo "Done. Next step: run 'flutter run' from project root."
