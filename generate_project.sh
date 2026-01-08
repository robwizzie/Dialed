#!/bin/bash

# Generate a working Xcode project for Dialed
# This creates the project structure that Xcode can open

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

PROJECT_NAME="Dialed"
BUNDLE_ID="com.dialed.app"

echo "🚀 Generating Xcode project for $PROJECT_NAME..."

# Create project directory structure
mkdir -p "${PROJECT_NAME}.xcodeproj"
mkdir -p "${PROJECT_NAME}"

# Create a minimal project.pbxproj file
# This is a simplified version that Xcode can open and then regenerate properly

cat > "${PROJECT_NAME}.xcodeproj/project.pbxproj" << 'PBXPROJ_END'
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		MainGroup = {
			isa = PBXGroup;
			children = (
				AppGroup,
			);
			sourceTree = "<group>";
		};
		AppGroup = {
			isa = PBXGroup;
			children = (
			);
			path = Dialed;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		MainTarget = {
			isa = PBXNativeTarget;
			buildConfigurationList = MainConfigList;
			buildPhases = (
			);
			buildRules = (
			);
			dependencies = (
			);
			name = "Dialed";
			productName = "Dialed";
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		ProjectObject = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
			};
			buildConfigurationList = ProjectConfigList;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = MainGroup;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				MainTarget,
			);
		};
/* End PBXProject section */

/* Begin XCBuildConfiguration section */
		DebugConfig = {
			isa = XCBuildConfiguration;
			buildSettings = {
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				SDKROOT = iphoneos;
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		ReleaseConfig = {
			isa = XCBuildConfiguration;
			buildSettings = {
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				SDKROOT = iphoneos;
				SWIFT_VERSION = 5.0;
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		MainConfigList = {
			isa = XCConfigurationList;
			buildConfigurations = (
				DebugConfig,
				ReleaseConfig,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		ProjectConfigList = {
			isa = XCConfigurationList;
			buildConfigurations = (
				DebugConfig,
				ReleaseConfig,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = ProjectObject;
}
PBXPROJ_END

echo "✅ Basic project structure created"
echo ""
echo "⚠️  This is a minimal template. You still need to:"
echo "   1. Open ${PROJECT_NAME}.xcodeproj in Xcode"
echo "   2. Xcode will migrate/fix the project"
echo "   3. Add your source files"
echo ""
echo "Better approach: Use the manual setup in QUICKSTART.md"
echo ""

PBXPROJ_END

chmod +x generate_project.sh

echo "✅ Script created: generate_project.sh"
