# Dialed - Setup Guide

## Quick Start

### Option 1: Manual Xcode Setup (Recommended for now)

1. **Create new Xcode project:**
   ```
   - Open Xcode 15+
   - File → New → Project
   - iOS → App
   - Product Name: Dialed
   - Interface: SwiftUI
   - Storage: None (we use SwiftData)
   - Minimum Deployment: iOS 17.0
   ```

2. **Add HealthKit Capability:**
   ```
   - Select project in navigator
   - Select "Dialed" target
   - Signing & Capabilities tab
   - Click "+ Capability"
   - Add "HealthKit"
   ```

3. **Replace default files:**
   ```
   - Delete the auto-generated ContentView.swift, DialedApp.swift, etc.
   - Drag all files from Dialed/Dialed/ into your Xcode project
   - Organize into groups matching the folder structure
   ```

4. **Copy Info.plist entries:**
   ```
   - Copy the HealthKit permission strings from:
     Dialed/Dialed/Resources/Info.plist
   - Into your project's Info.plist
   ```

### Option 2: Command Line (Future)

We'll add an automated Xcode project generator script soon.

## File Organization in Xcode

Create these groups in Xcode Navigator (⌘1):

```
Dialed/
├── App/
│   ├── DialedApp.swift
│   ├── AppState.swift
│   └── ContentView.swift
├── Models/
│   ├── UserSettings.swift
│   ├── DayLog.swift
│   ├── ChecklistItem.swift
│   ├── FoodEntry.swift
│   └── WorkoutLog.swift
├── Services/
│   ├── ScoringEngine.swift
│   ├── HealthKitManager.swift
│   └── HealthDataSyncService.swift
├── ViewModels/
│   └── (empty for now)
├── Views/
│   ├── Today/
│   │   └── TodayView.swift
│   ├── Log/
│   │   └── LogView.swift
│   ├── Calendar/
│   │   └── CalendarView.swift
│   ├── Trends/
│   │   └── TrendsView.swift
│   ├── Settings/
│   │   └── SettingsView.swift
│   └── Onboarding/
│       └── OnboardingFlowView.swift
├── Utilities/
│   ├── AppColors.swift
│   └── Constants.swift
└── Resources/
    └── Info.plist
```

## Testing Setup

1. **Add Test Target (if not already created):**
   ```
   - File → New → Target
   - iOS → Unit Testing Bundle
   - Name: DialedTests
   ```

2. **Add test files:**
   ```
   - Drag Tests/ScoringEngineTests.swift into DialedTests group
   - Ensure "Dialed" is checked in Target Membership
   ```

3. **Import main module:**
   ```swift
   @testable import Dialed
   ```

4. **Run tests:**
   ```
   - Product → Test (⌘U)
   - Or click diamond icon next to test class/function
   ```

## Required Devices/Apps for Full Functionality

### Hardware
- ✅ iPhone with iOS 17+ (HealthKit requires physical device)
- ✅ Apple Watch (for workout auto-detection)
- ✅ RingConn Smart Ring (for sleep tracking)
- ⚠️ Smart water bottle (optional, can manual log)

### Apps that sync to Apple Health
- **RingConn App** → writes sleep data to HealthKit
  - Enable all sleep permissions
  - Enable HRV sync

- **Water Tracking App** (choose one):
  - HiDrate Spark app (for HiDrate bottle)
  - WaterH (generic water tracking)
  - Ensure "Write to Apple Health" is enabled

- **Optional: Nutrition Apps**
  - MyFitnessPal (can write to HealthKit)
  - LoseIt
  - Cronometer
  - If you use these, Dialed can auto-pull protein/calories

## Verify HealthKit Integration

After setting up, verify HealthKit is working:

1. Run app on physical device
2. Go through onboarding (when built)
3. Grant HealthKit permissions
4. Check Settings → Privacy → Health → Dialed
5. Verify these are enabled:
   - Sleep Analysis ✅
   - Workouts ✅
   - Water ✅
   - Steps ✅
   - Active Energy ✅
   - Heart Rate Variability ✅

## Common Issues

### "HealthKit is not available"
- HealthKit only works on physical iOS devices
- Simulator will show this error
- Deploy to iPhone for testing

### "No sleep data found"
- RingConn app must sync to Apple Health
- Check RingConn app settings
- Verify data appears in Apple Health app
- Sleep data lags by ~30 minutes after waking

### "No workouts detected"
- Ensure Apple Watch workout was saved
- Check Apple Health → Browse → Activity → Workouts
- Workout must be saved to Health for detection

### "Water not syncing"
- Check water bottle app permissions
- Some apps don't write to HealthKit automatically
- May need to enable in app settings
- Fallback: Manual water entry works fine

## Development Workflow

1. **Work on feature branch:**
   ```bash
   git checkout -b feature/onboarding-flow
   ```

2. **Test frequently:**
   - Use SwiftUI Previews for quick UI iteration
   - Run unit tests (⌘U) after logic changes
   - Deploy to device for HealthKit testing

3. **Commit working code:**
   ```bash
   git add .
   git commit -m "Add onboarding profile setup screen"
   ```

## Next Steps

See README.md for the full roadmap.

Current priority: **Phase 3 - Onboarding Flow**

Files to create next:
- `Views/Onboarding/WelcomeView.swift`
- `Views/Onboarding/ProfileSetupView.swift`
- `Views/Onboarding/TargetsSetupView.swift`
- `Views/Onboarding/PermissionsView.swift`
