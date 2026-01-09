#!/bin/bash

# Dialed App - Xcode Project Generator
# This script creates a proper Xcode project structure

set -e

echo "🚀 Creating Dialed Xcode Project..."

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
XCODE_PROJECT_DIR="$PROJECT_DIR/DialedApp"

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Error: Xcode is not installed or xcodebuild is not in PATH"
    exit 1
fi

# Clean up any existing project
if [ -d "$XCODE_PROJECT_DIR" ]; then
    echo "⚠️  Removing existing DialedApp directory..."
    rm -rf "$XCODE_PROJECT_DIR"
fi

# Create new directory
mkdir -p "$XCODE_PROJECT_DIR"
cd "$XCODE_PROJECT_DIR"

echo "📦 Creating new Xcode project..."

# Create a new iOS app project using xcodebuild
# Note: We'll use swift package init then convert it
cat > Package.swift << 'EOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dialed",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Dialed", targets: ["Dialed"])
    ],
    targets: [
        .target(name: "Dialed"),
        .testTarget(name: "DialedTests", dependencies: ["Dialed"])
    ]
)
EOF

# Create the proper directory structure
mkdir -p Sources/Dialed
mkdir -p Tests/DialedTests

echo "📁 Copying source files..."

# Copy all source files
cp -r "$PROJECT_DIR/Dialed/Dialed/App" Sources/Dialed/
cp -r "$PROJECT_DIR/Dialed/Dialed/Models" Sources/Dialed/
cp -r "$PROJECT_DIR/Dialed/Dialed/Services" Sources/Dialed/
cp -r "$PROJECT_DIR/Dialed/Dialed/Views" Sources/Dialed/
cp -r "$PROJECT_DIR/Dialed/Dialed/ViewModels" Sources/Dialed/ 2>/dev/null || true
cp -r "$PROJECT_DIR/Dialed/Dialed/Utilities" Sources/Dialed/
cp -r "$PROJECT_DIR/Dialed/Dialed/Resources" Sources/Dialed/

# Copy tests
cp "$PROJECT_DIR/Dialed/Dialed/Tests/"* Tests/DialedTests/ 2>/dev/null || true

echo "✅ Project structure created!"
echo ""
echo "📝 MANUAL STEPS REQUIRED:"
echo ""
echo "1. Open Xcode"
echo "2. File → New → Project"
echo "3. Choose: iOS → App"
echo "4. Settings:"
echo "   - Product Name: Dialed"
echo "   - Interface: SwiftUI"
echo "   - Storage: None"
echo "   - Language: Swift"
echo "   - Organization Identifier: com.yourname.dialed"
echo "   - Minimum Deployment: iOS 17.0"
echo "5. Save to: $XCODE_PROJECT_DIR"
echo "6. Delete auto-generated files (ContentView.swift, DialedApp.swift)"
echo "7. Drag all folders from Sources/Dialed/ into your Xcode project"
echo "8. Add HealthKit capability:"
echo "   - Select project → Target → Signing & Capabilities"
echo "   - Click '+ Capability' → Add 'HealthKit'"
echo "9. Copy Info.plist entries from Resources/Info.plist"
echo "10. Build and run on a physical device!"
echo ""
echo "See SETUP.md for detailed instructions."
echo ""

# Actually, let's just provide the manual instructions
rm -rf "$XCODE_PROJECT_DIR"
