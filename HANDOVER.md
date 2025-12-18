# State Handover

## Active Task: Fixing Intersection Display
- **Context**: The "No intersection / No matrix" message persists even when content is correctly placed after loading a show.
- **Next Steps**:
    1.  Investigate `_loadShow` logic in `lib/ui/tabs/video_tab.dart` and `lib/ui/widgets/layer_controls.dart`.
    2.  Verify `_calculateIntersection` is called correctly after show load.
    3.  Check media player initialization timing.

## Recent Context
- Open files: `layer_controls.dart`, `video_tab.dart`.
