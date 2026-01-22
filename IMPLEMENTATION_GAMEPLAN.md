# Dialed App - Complete Customization & Enhancement Gameplan

## Current State Analysis
- ✅ Basic workout logging with exercise/weight/reps tracking
- ✅ Notification system created but not properly initialized
- ✅ Fixed scoring with all categories always counted
- ❌ No user customization of what to track
- ❌ No photo capabilities
- ❌ Workout tracking doesn't support set-by-set tracking
- ❌ No goal setting or progress visualization
- ❌ Notifications not firing (not initialized in app delegate)

---

## Phase 1: Tracking Customization System

### 1.1 Tracking Preferences Model
**File**: `Models/TrackingPreferences.swift`

```swift
struct TrackingPreferences {
    var trackSleep: Bool = true           // 20 points
    var trackWorkout: Bool = true         // 20 points (10 completion + 10 quality)
    var trackMile: Bool = true            // 15 points (7 completion + 8 quality)
    var trackWater: Bool = true           // 10 points
    var trackProtein: Bool = true         // 27 points (25 + 2 bonus)
    var trackChecklist: Bool = true       // 10 points

    // Total available: 102 points (with protein bonus)
    // Cap at 100 in scoring
}
```

### 1.2 Dynamic Scoring Algorithm
**File**: `Services/ScoringEngine.swift` (UPDATE)

**Strategy**: Redistribute points proportionally among enabled categories
- Calculate total points available from enabled categories
- Scale each category's contribution to maintain 100-point max
- Example: If sleep disabled, redistribute 20 points proportionally

**Formula**:
```
enabledTotal = sum of all enabled category points
scaleFactor = 100 / enabledTotal
adjustedPoints[category] = basePoints[category] * scaleFactor
```

### 1.3 Tracking Settings UI
**File**: `Views/Settings/TrackingSettingsView.swift` (NEW)

**Sections**:
1. Health & Fitness
   - Sleep (20 pts) - toggle + description
   - Workouts (20 pts)
   - Mile Run (15 pts)
2. Nutrition
   - Protein (27 pts)
   - Water (10 pts)
3. Routine
   - Daily Checklist (10 pts)

**Features**:
- Show point value for each category
- Show adjusted score calculation preview
- Warning when disabling categories
- Beautiful toggles with gradients

### 1.4 UI Conditional Rendering
**Files to Update**:
- `TodayView.swift` - hide disabled sections
- `ProgressSection` - hide disabled progress bars
- `ActivityTiles` - hide disabled tiles
- Navigation/tabs - adjust based on preferences

---

## Phase 2: Enhanced Workout Tracking

### 2.1 Set-by-Set Tracking
**File**: `Models/WorkoutSet.swift` (NEW)

```swift
@Model
final class WorkoutSet {
    var id: UUID
    var setNumber: Int         // 1, 2, 3, etc.
    var reps: Int
    var weightLbs: Double
    var restSeconds: Int?      // Rest time after this set
    var notes: String?
    var completedAt: Date
    var exercise: WorkoutExercise?  // Relationship
}
```

**Update WorkoutExercise**:
- Add `@Relationship var sets: [WorkoutSet]?`
- Remove top-level reps/weight (calculate from sets)

### 2.2 Goal Setting System
**File**: `Models/ExerciseGoal.swift` (NEW)

```swift
@Model
final class ExerciseGoal {
    var id: UUID
    var exerciseName: String
    var targetWeight: Double?    // Target weight to hit
    var targetReps: Int?         // Target reps at weight
    var targetDate: Date?        // When to achieve by
    var notes: String?
    var createdAt: Date
    var achieved: Bool = false
    var achievedAt: Date?
}
```

### 2.3 Progress Visualization
**File**: `Views/Workout/WorkoutProgressView.swift` (NEW)

**Features**:
- Line chart showing weight progression over time
- Bar chart for volume (sets × reps × weight)
- Personal records (PRs) highlighted
- Goal progress indicators
- Filter by exercise
- Date range selector

**Libraries Needed**: Swift Charts (built-in iOS 16+)

### 2.4 Enhanced Workout Log Sheet
**File**: `Views/Today/Components/WorkoutLogSheet.swift` (UPDATE)

**Changes**:
- Add set-by-set entry UI
- "Add Set" button for each exercise
- Show previous session's sets for comparison
- Rest timer between sets
- Swipe to delete sets
- Reorder sets (drag handle)

**UI Flow**:
```
Exercise: Bench Press
[Previous: 3 sets × 10 reps @ 185 lbs]

Set 1: 185 lbs × 10 reps [✓] Rest: 90s
Set 2: 185 lbs × 8 reps  [✓] Rest: 90s
Set 3: 185 lbs × 6 reps  [✓]
[+ Add Set]
```

### 2.5 Workout History View
**File**: `Views/Workout/WorkoutHistoryView.swift` (NEW)

**Features**:
- Calendar view showing workout days
- List of all workouts with date/type/score
- Tap to see detailed workout with exercises/sets
- Filter by workout type
- Search exercises
- Export to CSV option

---

## Phase 3: Photo Integration

### 3.1 Photo Storage System
**File**: `Services/PhotoManager.swift` (NEW)

**Strategy**:
- Store photos in app's Documents directory
- Save filenames to SwiftData
- Support taking photos and selecting from library
- Compress for storage efficiency
- Delete photos when workout deleted

### 3.2 Photo Model
**File**: `Models/WorkoutPhoto.swift` (NEW)

```swift
@Model
final class WorkoutPhoto {
    var id: UUID
    var filename: String        // Stored in Documents
    var capturedAt: Date
    var workoutLog: WorkoutLog?
    var notes: String?
}
```

**Update WorkoutLog**:
- Add `@Relationship var photos: [WorkoutPhoto]?`

### 3.3 Photo Capture UI
**File**: `Views/Workout/PhotoCaptureSheet.swift` (NEW)

**Features**:
- Camera view for taking photos
- Photo picker for selecting from library
- Preview with filters (optional)
- Add caption/notes
- Multiple photos per workout
- Grid view of all photos

### 3.4 Photo Gallery
**File**: `Views/Workout/WorkoutPhotoGalleryView.swift` (NEW)

**Features**:
- Grid of all workout photos
- Filter by date range
- Filter by workout type
- Full-screen view with swipe
- Share photos
- Delete photos

### 3.5 Photo Notification
**Update**: `NotificationManager.swift`

**New Notification Type**: `workoutPhotoReminder`
- Triggered when workout is completed
- Prompt: "📸 Great workout! Add a progress photo?"
- Action buttons: "Take Photo" / "Later"
- Deep link to photo capture

---

## Phase 4: Fix Notifications

### 4.1 Notification Registration
**File**: `DialedApp.swift` (UPDATE)

**Required Changes**:
```swift
@main
struct DialedApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Register notification categories on app launch
        Task {
            await NotificationManager.shared.registerCategories()
            await NotificationManager.shared.checkAuthorizationStatus()
        }
    }
}
```

### 4.2 App Delegate for Notifications
**File**: `AppDelegate.swift` (NEW)

```swift
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification) async
                               -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }

    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse) async {
        // Handle deep links based on notification category
    }
}
```

### 4.3 Notification Categories Registration
**File**: `NotificationManager.swift` (UPDATE)

**Add**:
```swift
func registerCategories() async {
    let categories: Set<UNNotificationCategory> = [
        // Task Reminder with actions
        UNNotificationCategory(
            identifier: NotificationCategory.taskReminder.rawValue,
            actions: [
                UNNotificationAction(identifier: "COMPLETE", title: "Mark Done"),
                UNNotificationAction(identifier: "SNOOZE", title: "Remind in 15m")
            ],
            intentIdentifiers: []
        ),
        // Workout Photo Reminder
        UNNotificationCategory(
            identifier: NotificationCategory.workoutPhotoReminder.rawValue,
            actions: [
                UNNotificationAction(identifier: "TAKE_PHOTO", title: "Take Photo"),
                UNNotificationAction(identifier: "LATER", title: "Later")
            ],
            intentIdentifiers: []
        )
    ]

    UNUserNotificationCenter.current().setNotificationCategories(categories)
}
```

### 4.4 Test Notifications
**File**: `Views/Settings/NotificationsSettingsView.swift` (UPDATE)

**Add**: "Test Notification" button in settings
- Sends immediate test notification
- Helps debug if notifications are working

---

## Phase 5: Branding & UI Polish

### 5.1 Logo Integration
**Files to Update**:
- `Assets.xcassets/AppIcon.appiconset` - Already set up
- Launch screen - Add logo
- Settings header - Show logo
- About section - Logo with version

### 5.2 Color Consistency Audit
**File**: `Utilities/AppColors.swift` (UPDATE)

**Ensure consistent use of**:
- Primary gradients: Blue to cyan
- Success gradients: Green to mint
- Warning gradients: Orange to yellow
- Danger gradients: Red to pink
- Workout gradients: Green to mint
- Mile gradients: Orange to red
- Sleep gradients: Indigo to purple

### 5.3 Typography Consistency
**Standardize**:
- Headers: `.headline.bold()`
- Body: `.body`
- Captions: `.caption` or `.caption2`
- Numbers: `.monospacedDigit()`

### 5.4 Spacing Consistency
**Standard spacing values**:
- Compact: 8pt
- Default: 12pt
- Comfortable: 16pt
- Spacious: 20pt
- Section gap: 24pt

### 5.5 Glass Morphism Audit
**Ensure all cards use**:
- `.ultraThinMaterial` or `.regularMaterial`
- Corner radius: 12pt (standard), 16pt (elevated)
- Border: `.white.opacity(0.1)`, lineWidth: 0.5
- Shadow for elevated: `.shadow(color: .black.opacity(0.1), radius: 8)`

---

## Phase 6: Additional Enhancements

### 6.1 Onboarding Flow
**File**: `Views/Onboarding/OnboardingView.swift` (NEW)

**Screens**:
1. Welcome + Logo
2. What do you want to track? (Toggle selections)
3. Set daily targets (protein/water)
4. Enable notifications
5. Grant HealthKit permissions
6. Add first custom task (optional)
7. Ready to go!

### 6.2 Workout Templates
**File**: `Models/WorkoutTemplate.swift` (NEW)

**Feature**: Save workout routines as templates
- "Push Day Template": Bench Press, Shoulder Press, Triceps
- Quick-start workouts from templates
- Suggested rest times per exercise

### 6.3 Statistics Dashboard
**File**: `Views/Stats/StatsDashboardView.swift` (NEW)

**Metrics**:
- Average daily score (weekly/monthly)
- Streak calendar heatmap
- Category breakdown (pie chart)
- Workout frequency
- PRs achieved
- Photos timeline

### 6.4 Social/Sharing Features
**Optional but cool**:
- Share daily score to social media
- Share progress photos
- Share workout summary
- Generate shareable cards with branding

### 6.5 Export & Backup
**Features**:
- Export all data to JSON
- Import data from backup
- Email data export
- iCloud sync (future)

---

## Implementation Order (Priority)

### Critical (Do First):
1. ✅ Fix notifications (Phase 4) - User needs this working
2. ✅ Enhanced workout tracking with sets (Phase 2.1, 2.2, 2.4) - Core feature
3. ✅ Photo integration (Phase 3) - User explicitly requested
4. ✅ Tracking customization (Phase 1) - Makes app usable for different users

### Important (Do Next):
5. Progress visualization (Phase 2.3, 2.5)
6. Branding polish (Phase 5)
7. Workout history view
8. Goal setting UI

### Nice to Have (If Time):
9. Onboarding flow
10. Workout templates
11. Stats dashboard
12. Export features

---

## Technical Requirements

### New Dependencies:
- Swift Charts (built-in iOS 16+) ✅
- PhotoKit framework ✅
- FileManager for photo storage ✅

### Database Schema Updates:
- Add `WorkoutSet` model
- Add `WorkoutPhoto` model
- Add `ExerciseGoal` model
- Add `TrackingPreferences` to UserSettings
- Update `WorkoutExercise` relationships

### Notification Updates:
- Add AppDelegate
- Register categories
- Handle actions
- Add photo reminder notification

### File Structure:
```
Dialed/
├── Models/
│   ├── WorkoutSet.swift (NEW)
│   ├── WorkoutPhoto.swift (NEW)
│   ├── ExerciseGoal.swift (NEW)
│   ├── TrackingPreferences.swift (NEW)
├── Services/
│   ├── PhotoManager.swift (NEW)
│   ├── NotificationManager.swift (UPDATE)
│   ├── ScoringEngine.swift (UPDATE)
├── Views/
│   ├── Onboarding/ (NEW)
│   ├── Workout/
│   │   ├── WorkoutProgressView.swift (NEW)
│   │   ├── WorkoutHistoryView.swift (NEW)
│   │   ├── PhotoCaptureSheet.swift (NEW)
│   │   ├── WorkoutPhotoGalleryView.swift (NEW)
│   ├── Settings/
│   │   ├── TrackingSettingsView.swift (NEW)
├── AppDelegate.swift (NEW)
```

---

## Testing Checklist

### Notifications:
- [ ] Task reminders fire at scheduled times
- [ ] Completion notifications show immediately
- [ ] Score update notifications show on increase
- [ ] Photo reminder after workout completion
- [ ] Daily summary at configured time
- [ ] Notification actions work (mark done, take photo, etc.)

### Workout Tracking:
- [ ] Add exercise with multiple sets
- [ ] Edit set weight/reps
- [ ] Delete sets
- [ ] Reorder sets
- [ ] View previous session comparison
- [ ] Set goals for exercises
- [ ] Track progress toward goals
- [ ] View workout history

### Photos:
- [ ] Take photo with camera
- [ ] Select photo from library
- [ ] Add multiple photos to workout
- [ ] View photo gallery
- [ ] Delete photos
- [ ] Share photos

### Customization:
- [ ] Toggle tracking categories on/off
- [ ] Score recalculates correctly
- [ ] Disabled sections hidden in UI
- [ ] Targets adjust based on preferences
- [ ] Notifications respect preferences

---

## Estimated Complexity

**High Complexity** (3-4 hours each):
- Set-by-set workout tracking with UI
- Photo integration system
- Dynamic scoring with customization
- Progress charts and visualization

**Medium Complexity** (1-2 hours each):
- Fix notifications with AppDelegate
- Goal setting system
- Workout history view
- Photo gallery

**Low Complexity** (<1 hour each):
- Tracking preferences UI
- Conditional UI rendering
- Branding polish
- Settings toggles

**Total Estimated Time**: 20-25 hours of development

---

## Success Criteria

✅ User can customize what they track
✅ Score adjusts dynamically based on preferences
✅ Workout tracking supports set-by-set entry
✅ Users can set and track workout goals
✅ Photos can be added to workouts easily
✅ Notifications fire reliably
✅ Photo reminder appears after workouts
✅ UI is beautiful and consistent throughout
✅ Progress is easily viewable
✅ App feels professional and polished
