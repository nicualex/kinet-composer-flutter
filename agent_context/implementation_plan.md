# Video Workflow Refactoring

## Goal
Simplify the video editing workflow by defaulting to Zoom/Pan mode and automatically handling cropping and resolution during export based on the overlap between the video and the LED matrix.

## Proposed Changes

### UI (`lib/ui/tabs/video_tab.dart`)
#### [MODIFY] [video_tab.dart](file:///c:/Users/nicua/Documents/Development/Antigravity/kinet-composer-flutter/lib/ui/tabs/video_tab.dart)
- **State**:
    - Remove `_isEditingCrop`.
    - Remove `EditMode` enum usage (or force `zoom`).
    - Add `Rect? _currentIntersection` to store the calculated intersection for UI display.
- **Components**:
    - Remove "Zoom/Pan" and "Crop" toggle buttons.
    - Add "Matrix Intersection" info section in sidebar: `X: [min-max], Y: [min-max]`, `Resolution: WxH`.
- **Logic**:
    - `_autoFitVideoToMatrix`: Keep existing logic.
    - `TransformGizmo`:
        - `isCropMode`: Always `false` (Visual cropping is gone, we only zoom/pan).
        - `editMode`: Always `EditMode.zoom` (allows scaling/translation).
        - `onUpdate`: Trigge logic to calculate `_currentIntersection` and update state.

### Export Logic (`lib/ui/tabs/video_tab.dart`)
#### [MODIFY] [video_tab.dart](file:///c:/Users/nicua/Documents/Development/Antigravity/kinet-composer-flutter/lib/ui/tabs/video_tab.dart)
- **`_exportVideo`**:
    - Rely *exclusively* on the intersection of `VideoRect` and `MatrixRect`.
    - If no intersection, warn/block export.
    - **Resolution**: Output `width` = `intersection.width / 10.0`, `height` = `intersection.height / 10.0` (matching existing grid logic).
    - **Source Crop**: Calculate the portion of the video source (after transform scaling) that corresponds to the intersection rect.

## Verification Plan
1. **Layout**: Confirm crop/zoom buttons are gone.
2. **Interaction**: Confirm dragging/scrolling on the video immediately pans/zooms.
3. **Feedback**: Verify "Intersection" coordinates update as you drag.
4. **Export**:
    - Pan video so it only partially covers the matrix.
    - Export.
    - Play result: Should be a small video matching the matrix resolution, containing only the visible overlapping part.
