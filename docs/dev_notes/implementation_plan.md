# Visual Crop Editing Implementation Plan

## Goal
Implement interactive crop handles (visual cropping) in `TransformGizmo` and integrated into `VideoTab`.

## Proposed Changes

### Widget (`lib/ui/widgets/`)
#### [MODIFY] [transform_gizmo.dart](file:///c:/Users/nicua/OneDrive/Documents/AntiGravity/kinet-composer-flutter/lib/ui/widgets/transform_gizmo.dart)
- **Props**: Add `onCropUpdate`.
- **Logic**:
    - When `isCropMode` is true:
        - Draw a semi-transparent overlay over the whole child.
        - "Cut out" the crop rect (or just draw borders).
        - Place handles at the corners of the *Crop Rect*.
        - **Math**: Convert drag delta (pixels) -> Percentage of the Container Size.
- **Crop Handles**:
    - TopLeft, TopRight, etc. adjust `x,y` and `width,height`.

### UI (`lib/ui/tabs/`)
#### [MODIFY] [video_tab.dart](file:///c:/Users/nicua/OneDrive/Documents/AntiGravity/kinet-composer-flutter/lib/ui/tabs/video_tab.dart)
- **State**: Add `bool _isEditingCrop = false`.
- **Logic**:
    - If `_isEditingCrop` is active:
        - Render `Video` *without* `ClipRect` (User needs to see what to crop).
        - Pass `isCropMode: true` to Gizmo.
    - If `!_isEditingCrop`:
        - Render `Video` *with* `ClipRect` (User sees final result).
        - Pass `isCropMode: false`.
- **Property Panel**:
    - [DELETE] "Change Video" button.
    - [NEW] "Load Video" button (Icon: upload/folder).
        - Action: `_pickVideo()`.
    - [NEW] "Save Video" button (Icon: save).
        - Action: `_exportVideo()`.
        - Logic: checks for `ffmpeg.exe` and runs it via `Process.run`.
        - Shows "Exporting..." dialog.

    - [NEW] "Lock Aspect Ratio" Checkbox.
        - Affects `TransformGizmo` scaling behavior.
        - Default: `true` (Maintain ratio).
    - [Modify] "Load Video":
        - Reset `show.mediaTransform` to identity.
        - Clear `_tempTransform`.
        - Reset `_isEditingCrop` to false.
    - [NEW] Auto-Fit Video:
        - Logic: On video load, calculate scale to CONTAIN video within fixture matrix bounds (ensure full visibility).
        - Implementation: `_autoFitVideoToMatrix` in `VideoTab`.

### [MODIFY] [transform_gizmo.dart](file:///c:/Users/nicua/OneDrive/Documents/AntiGravity/kinet-composer-flutter/lib/ui/widgets/transform_gizmo.dart)
- **Refactor**: Enable Panning in View Mode.
    - Extract Pan Gesture Detector to global stack in Gizmo.
    - Allow video translation even when not in explicit "Edit Mode".
    - Uses "Global Delta" math to ensure 1:1 proportionality regardless of zoom.

## New Features Plan
1.  **Blank Project on Startup**:
    - Modify `ShowState`: Remove nullable `_currentShow`. Initialize it in constructor (or `init`) with `newShow()`.
2.  **Edit Project Name**:
    - Modify `ShowState`: Add `void updateName(String name)`.
    - Modify `ProjectTab`: Replace `Text` widget for name with a `Row` containing an `EditableText` or `TextField`, or a popup dialog when clicking the name.

## Video Edit Refinement
- **Goal**: Separate Zoom (Scale/Rotate) and Crop interactions.
- **UI**: Add "Zoom / Crop" toggle switch when in "Edit Video" mode.
- **Logic**:
  - `video_tab.dart`: Track `_editMode` (Zoom vs Crop).
  - `transform_gizmo.dart`:
    - If Zoom mode: Show only Blue/Green handles and Border.


## Effects Library (Hybrid Approach)
- **Goal**: Tunable effects (Speed, Density) with real-time feedback.
- **Strategy**:
  - **Preview**: Render using Flutter `CustomPainter` logic (Real-time 60fps).
  - **Export**: Render using FFmpeg `lavfi` commands that approximate the visual.
- **Components**:
  - `EffectService`:
    - `getPreviewPainter(type, params)`: Returns a CustomPainter.
    - `getFFmpegFilter(type, params)`: Returns the `-vf` string for FFmpeg.
  - `VideoTab`:
    - Add `EffectMode` state (Video vs Effect).
    - If Effect: Show `EffectRenderer` widget instead of `Video` player.
    - Properties Panel: Show Sliders for `customParams` (Speed, Density).
  - **Effects**:
    - **Rainbow Wave**: Moving Linear Gradient. (FFmpeg: `geq` filter with sin waves).
    - **Static Noise**: Random colored noise. (FFmpeg: `noise` filter).
- **UI**:
  - Rename tab to "Videos / Effects".
  - Add "Effects" section in panel.


## Video Export Plan (Windows)
- **Strategy**: Bundle/Download `ffmpeg.exe`.
- **Logic**:
    1.  Check if `ffmpeg.exe` exists in `assets/` or a known location.
    2.  If not, prompt user to download or error (For now: Assume valid ffmpeg path or user provides it).
        - *Better*: Include `ffmpeg.exe` in `windows/runner/resources` (if license allows) OR just ask user to install it.
        - *Simplest for Agent*: Use `Process.run('ffmpeg', ...)` assuming it is in PATH. If not found, tell user to install FFmpeg.
    3.  Command construction remains similar but uses standard CLI syntax.
    4.  Execute via `Process.run()`.
        - Default State: Show "Edit Transform" (or "Crop") button.
        - Edit Mode State:
            - Show "Apply Changes" (Green?).
                - Action: Commit changes to `ShowState`, exit edit mode.
            - Show "Cancel" (Red/Grey?).
                - Action: Revert to state before editing, exit edit mode.

## Video Controls Plan
- **Goal**: Add Play, Pause, and Stop controls.
- **UI**: Row of buttons in Property Panel.
    - [Play/Pause] Icon(Icons.play_arrow / pause).
    - [Stop] Icon(Icons.stop).
- **Logic**:
    - `player.playOrPause()`.
    - `player.stop()` resets to beginning.

## Verification
1.  **Enable Crop**: Toggle switch.
2.  **Enter Edit Mode**: Click "Edit Crop".
    - Video should un-clip (show full).
    - Crop rect border should appear.
3.  **Adjust**:
    - Drag crop corners -> Updates crop rect.
    - Drag crop center -> Moves crop rect.
4.  **Exit Edit Mode**: Click "Done".

## Video Controls Plan
- **Goal**: Add Play, Pause, and Stop controls for the loaded video.
- **UI**: Add buttons in the "Video Properties" panel.
    - [Play/Pause] Icon button.
    - [Stop] Icon button.
- **Logic**:
    - Use `player.playOrPause()` for toggle.
    - Use `player.stop()` or `player.seek(Duration.zero); player.pause();` for stop.
    - Listen to `player.stream.playing` to update the Play/Pause icon.
