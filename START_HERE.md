# 🚀 START HERE - 3 Minute Setup

You cloned the repo but Xcode can't open it because there's no `.xcodeproj` file. Here's the **fastest** way to get running:

## Method 1: Use Xcode GUI (Fastest - 3 minutes)

### Step 1: Create New Project (1 min)
1. Open **Xcode**
2. **File → New → Project** (or press ⇧⌘N)
3. Select: **iOS → App**
4. Click **Next**
5. Fill in:
   - **Product Name:** `Dialed`
   - **Team:** (your team or None)
   - **Organization Identifier:** `com.yourname.dialed`
   - **Interface:** `SwiftUI`
   - **Storage:** `None`
   - **Language:** `Swift`
6. Click **Next**
7. **Save to:** `/Users/robertwiscount/Desktop/DialedXcode`
   - (Different location than the clone - that's intentional!)
8. Click **Create**

### Step 2: Configure Project (30 sec)
1. In Xcode, select **Dialed** project (blue icon at top)
2. Select **Dialed** target
3. **General** tab:
   - Change **Minimum Deployments** to **iOS 17.0**
4. **Signing & Capabilities** tab:
   - Click **+ Capability**
   - Add **HealthKit**

### Step 3: Replace Files (1 min)
1. In Xcode navigator, **delete** these auto-generated files (right-click → Delete → Move to Trash):
   - `ContentView.swift`
   - `DialedApp.swift`

2. **Open Finder** to: `/Users/robertwiscount/Desktop/Dialed/Dialed/Dialed/`

3. **Drag these 5 folders** into Xcode (into the "Dialed" group):
   - `App`
   - `Models`
   - `Services`
   - `Views`
   - `Utilities`

4. When the dialog appears:
   - ✅ Check **"Copy items if needed"**
   - ✅ Check **"Create groups"**
   - ✅ Check **"Dialed"** target
   - Click **Finish**

### Step 4: Add HealthKit Permissions (30 sec)
1. In Xcode, find **Info.plist** (or Project → Target → Info tab)
2. Right-click → **Add Row**
3. Add this entry:
   - **Key:** `Privacy - Health Share Usage Description`
   - **Type:** String
   - **Value:** `Dialed needs access to your health data to automatically track sleep quality from RingConn, detect workouts from Apple Watch, and provide accurate daily scores.`

### Step 5: Build! (10 sec)
1. **Product → Build** (⌘B)
2. Should build successfully!
3. Connect your iPhone and **Product → Run** (⌘R)

---

## Method 2: One Command (If you're comfortable with terminal)

```bash
cd /Users/robertwiscount/Desktop/Dialed
open QUICKSTART.md
```

Follow the detailed steps there.

---

## ✅ Success!

You should now see:
- The Dialed app running on your iPhone
- A simple welcome screen
- Ability to tap "Get Started" and see the tab navigation

---

## 🐛 Issues?

**Build Error: "Cannot find HKHealthStore"**
- Make sure you added HealthKit capability in Step 2

**Build Error: "Cannot find DayLog"**
- Make sure you dragged all 5 folders in Step 3
- Check that files show "Dialed" target in File Inspector

**"No such module 'SwiftData'"**
- Make sure iOS deployment target is 17.0 (Step 2)

---

## 🎯 What's Next?

Once it's running:
1. Explore the code - check out `ScoringEngine.swift`
2. Run tests: **Product → Test** (⌘U)
3. I'll build the full onboarding flow next!

The app won't do much yet (just placeholder screens), but the foundation is solid and ready to build on.
