# UI Polish & Cleanup Implementation Plan

## Goal
Improve the visual aesthetics of the application to be more "fluid" with "transparencies", remove the top title code, and fix a reported crash in `ProjectTab`.

## User Review Required
> [!NOTE]
> The "fluidity" and "transparency" will be achieved by:
> 1.  Using a dark gradient background for the main window.
> 2.  Making the TabBar more modern (transparent background, pill indicators).
> 3.  Removing the default AppBar title.
> 4.  Using a refined Dark Theme with a more vibrant color scheme (Deep Purple & Cyan).

## Proposed Changes

### Core UI (`lib/ui/`)
#### [MODIFY] [home_screen.dart](file:///c:/Users/nicua/OneDrive/Documents/AntiGravity/kinet-composer-flutter/lib/ui/home_screen.dart)
- **Remove `AppBar` title**.
- **Container Gradient**: Wrap the `Scaffold` or `TabBarView` in a Container with a `LinearGradient` (Deep Charcoal to Black/Purple) to give depth.
- **Transparent AppBar**: Set `AppBar` background to `Colors.transparent` and use `elevation: 0`.
- **Modern TabBar**: Use a `TabBar` with a custom indicator (e.g., `BoxDecoration` with rounded corners) or just cleaner styling.

#### [MODIFY] [main.dart](file:///c:/Users/nicua/OneDrive/Documents/AntiGravity/kinet-composer-flutter/lib/main.dart)
- **Theme Update**: 
    - `scaffoldBackgroundColor`: `Colors.transparent` (so the gradient shows through if we wrap it, or just a dark color).
    - `useMaterial3`: `true`.
    - `colorScheme`: Dark brightness, Seed `DeepPurple`, Secondary `CyanAccent`.
    - `cardTheme`: Elevation 8, semi-transparent color (`Colors.white.withOpacity(0.05)`).
    - `appBarTheme`: Transparent.

### Components (`lib/ui/tabs/`)
#### [MODIFY] [project_tab.dart](file:///c:/Users/nicua/OneDrive/Documents/AntiGravity/kinet-composer-flutter/lib/ui/tabs/project_tab.dart)
- **Bug Fix**: Store `StreamSubscription` from `discovery.deviceStream` and `cancel()` it in `dispose()`.
- **UI Tweaks**: Use `Card` with transparency/blur updates from global theme.

## Verification Plan

### Automated Tests
- Run `flutter build windows` to ensure no compilation errors.

### Manual Verification
1.  **Run the App**: `flutter run -d windows`.
2.  **Visual Check**:
    - Confirm "Kinet Composer" title is gone.
    - Confirm background has a subtle gradient/depth.
    - Confirm Tabs look modern.
3.  **Discovery Test**:
    - Go to "Shows" tab (ProjectTab).
    - Start Discovery.
    - Switch tabs (to Setup or Video).
    - Wait a moment (simulate incoming packet).
    - **Verify**: No crash in console (`setState() called after dispose()` should be gone).

## Export Enhancements
### [MODIFY] [video_tab.dart](file:///c:/Users/nicua/OneDrive/Documents/AntiGravity/kinet-composer-flutter/lib/ui/tabs/video_tab.dart)
- **Calculate Matrix Resolution**: Iterate `ShowState.currentShow.fixtures` to determine the bounding box (width/height of the LED grid).
- **Update FFmpeg Command**:
    - **Scaling**: Add `scale=W:H:flags=lanczos` to match matrix resolution.
    - **Interpolation**: Add `minterpolate='mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1'` for high-quality motion compensation.
    - **Note**: This will be slow, so update the loading dialog text to warn the user.

## Interaction Improvements
### [MODIFY] [transform_gizmo.dart](file:///c:/Users/nicua/OneDrive/Documents/AntiGravity/kinet-composer-flutter/lib/ui/widgets/transform_gizmo.dart)
- **Add Double Tap Callback**: Add `VoidCallback? onDoubleTap` to `TransformGizmo`.
- **Gesture Detection**: Use `GestureDetector(onDoubleTap: ...)` within the gizmo stack.

### [MODIFY] [video_tab.dart](file:///c:/Users/nicua/OneDrive/Documents/AntiGravity/kinet-composer-flutter/lib/ui/tabs/video_tab.dart)
- **Implement `_fitToMatrix()`**: 
  - Calculate Matrix Bounds (max Width, max Height of fixtures * 10.0).
  - Calculate Video Visual Size (Video Width/Height).
  - **Auto Fit Logic**:
    - If `_lockAspectRatio` is FALSE: Scale X = MatrixW/VideoW, Scale Y = MatrixH/VideoH (Stretch).
    - If `_lockAspectRatio` is TRUE: Calculate `contain` scale (min of W_ratio, H_ratio).
    - Set Translate X, Y to center over matrix.
- **Hook up Callback**: Pass `_fitToMatrix` to `TransformGizmo.onDoubleTap`.
