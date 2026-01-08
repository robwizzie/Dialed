# Dialed - Quick Start Guide (5 minutes)

## Why You're Getting the Error

The repository contains Swift source files but not an Xcode project file (`.xcodeproj`). Xcode needs a project file to open the code.

## Fast Setup (Follow These Exact Steps)

### Step 1: Create New Xcode Project (2 min)

1. **Open Xcode 15 or later**

2. **File → New → Project** (or ⇧⌘N)

3. **Choose template:**
   - Select **iOS** tab
   - Select **App**
   - Click **Next**

4. **Project settings:**
   ```
   Product Name: Dialed
   Team: (your team or "None")
   Organization Identifier: com.yourname.dialed
   Interface: SwiftUI
   Storage: None (we'll use SwiftData)
   Language: Swift
   ☐ Include Tests (uncheck - we have custom tests)
   ```
   - Click **Next**

5. **Save location:**
   - Navigate to: `/Users/robertwiscount/Desktop/`
   - Create new folder: `DialedXcode`
   - Click **Create**

### Step 2: Configure Project Settings (1 min)

1. **Set minimum iOS version:**
   - Select **Dialed** project in navigator (blue icon at top)
   - Select **Dialed** target
   - General tab → Deployment Info
   - Change **Minimum Deployments** to: **iOS 17.0**

2. **Add HealthKit capability:**
   - Still in project settings
   - Click **Signing & Capabilities** tab
   - Click **+ Capability** button
   - Search for "HealthKit"
   - Double-click **HealthKit** to add it

### Step 3: Delete Auto-Generated Files (30 sec)

In the Xcode navigator, delete these files (Move to Trash):
- `ContentView.swift`
- `DialedApp.swift`
- `Assets.xcassets` (we'll add this back later)
- `Preview Content` folder

Your project should now be mostly empty.

### Step 4: Add Our Source Files (1 min)

1. **Open Finder** to: `/Users/robertwiscount/Desktop/Dialed/Dialed/Dialed/`

2. **Drag these folders** into Xcode (into the "Dialed" group):
   - `App` folder
   - `Models` folder
   - `Services` folder
   - `Views` folder
   - `Utilities` folder

3. **When prompted:**
   - ✅ Check "Copy items if needed"
   - ✅ Check "Create groups"
   - ✅ Check "Dialed" target
   - Click **Finish**

### Step 5: Add Info.plist Entries (1 min)

1. **In Xcode navigator**, find `Info.plist` (or select project → Target → Info tab)

2. **Right-click in the Info.plist** → Add Row

3. **Add these 3 entries:**

   **Entry 1:**
   ```
   Key: Privacy - Health Share Usage Description
   Type: String
   Value: Dialed needs access to your health data to automatically track sleep quality from RingConn, detect workouts from Apple Watch, monitor water intake from your smart water bottle, and provide accurate daily scores based on your actual metrics.
   ```

   **Entry 2:**
   ```
   Key: Privacy - Health Update Usage Description
   Type: String
   Value: Dialed can optionally write nutrition data to Apple Health to keep all your health metrics in one place.
   ```

   **Entry 3:**
   ```
   Key: Privacy - User Notifications Usage Description (if needed)
   Type: String
   Value: Dialed sends reminders for your daily routine (skincare, supplements, workout logging) to help you stay consistent and build streaks.
   ```

### Step 6: Add Tests (Optional - 30 sec)

1. **Create test target:**
   - File → New → Target
   - iOS → Unit Testing Bundle
   - Name: `DialedTests`
   - Click **Finish**

2. **Delete** the auto-generated test file

3. **Drag** `Tests/ScoringEngineTests.swift` from Finder into the DialedTests folder in Xcode
   - ✅ Check "DialedTests" target
   - Click **Finish**

### Step 7: Build & Run (30 sec)

1. **Select a physical device** (not simulator - HealthKit requires real device)
   - If you don't have one connected, select "Any iOS Device"

2. **Product → Build** (⌘B)
   - Should build successfully
   - You may see warnings - that's okay for now

3. **If you have a device connected:**
   - Product → Run (⌘R)
   - You should see the onboarding welcome screen!

---

## ✅ Success Checklist

Your project should now have:
- [x] iOS 17.0 minimum deployment
- [x] HealthKit capability enabled
- [x] All source files in proper groups
- [x] Info.plist with HealthKit permission descriptions
- [x] Builds without errors

## 🐛 Troubleshooting

### Build Error: "Cannot find type 'HKHealthStore'"
- **Fix**: Make sure HealthKit capability is added in Signing & Capabilities

### Build Error: "Cannot find 'DayLog' in scope"
- **Fix**: Make sure all files are added to the Dialed target
- Check: Select file → File Inspector (⌥⌘1) → Target Membership → Dialed should be checked

### Runtime Error: "HealthKit is not available"
- **Fix**: HealthKit only works on physical devices, not simulator
- Deploy to a real iPhone

### Files won't drag into Xcode
- **Fix**: Make sure you're dragging into the Dialed group (yellow folder), not the project
- Try: Right-click Dialed group → Add Files to "Dialed"

---

## Next Steps

Once the project is running:

1. **Explore the code:**
   - Check out `ScoringEngine.swift` - the brain of the app
   - Look at `HealthKitManager.swift` - automation engine

2. **Run the tests:**
   - Product → Test (⌘U)
   - All 11 tests should pass

3. **Ready for Phase 3:**
   - I'll build the full onboarding flow next
   - Then the Today screen with live scoring

---

## Still Having Issues?

Let me know what error you're seeing and I'll help troubleshoot!

Common issues:
- "Missing files" → Check Step 4
- "Build errors" → Check Step 5 (Info.plist)
- "HealthKit errors" → Check Step 2 (capability)
