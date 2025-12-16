# Video Editing Walkthrough

I have implemented the video editing functionality in the `VideoTab`. You can now load video files and adjust their appearance using the side panel.

## Changes
- **Updated `ShowState`**: Added `updateMedia` and `updateTransform` to manage video state.
- **Implemented `VideoTab`**:
    - **Video Player**: Uses `media_kit` to play the selected video file.
    - **Controls**: Simplified workflow. Zoom and Pan are always enabled. Crop is handled automatically on export.
    - **Matrix Intersection**: Shows real-time overlap info (X/Y Range, Resolution) to guide positioning.
    - **Transformations**: Added sliders for:
        - Scale X / Y
        - Rotation (0-360 degrees)
        - Position X / Y
- **Implemented Effects**:
    - **Effect Service**: Added tunable effects (Rainbow Wave, Static Noise).
    - **Effect Export**: Generates videos using FFmpeg filters (`geq`, `noise`) matching the visual effects.

## Verification Steps
1.  **Run the App**:
    ```powershell
    cd kinet-composer-flutter
    flutter run -d windows
    ```
2.  **Open Video Tab**: Click on the "Video" tab in the main navigation.
3.  **Load a Video**:
    - Click "Select Video Source" (or "Change Video" if one is loaded).
    - Choose a video file (.mp4, .mkv, etc.) from your computer.
4.  **Test Controls**:
    - **Play**: Confirm the video starts playing automatically (looping).
    - **Scale**: Drag the "Scale X" slider. The video should zoom in/out locally.
    - **Rotate**: Drag the "Rotation" slider. The video should rotate around its center.
    - **Position**: Drag "Position X/Y" sliders. The video should move within the black container.
5.  **Persist**: Switch to another tab (e.g., "Setup") and back to "Video". The video should still be there with your transform settings applied.
6.  **Test Effects**:
    - Select "Rainbow Wave" or "Static Noise" from the Effects Library.
    - Adjust sliders (Speed, Scale, Intensity).
    - Click "Save Video" to render the effect to an MP4 file using FFmpeg.
    - The app will automatically load the rendered effect video.
