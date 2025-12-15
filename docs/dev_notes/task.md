# Tasks

- [x] Implement Video Controls (Play, Pause, Stop)
- [x] Refactor Crop Workflow
    - [x] Add `_tempTransform` state to `VideoTab`
    - [x] Remove "Enable Crop" switch
    - [x] Implement "Crop" / "Edit" button logic
    - [x] Implement "Apply" / "Cancel" logic
- [x] Implement "Load Video" and "Save Video" buttons
- [x] Remove "Change Video" button
- [x] Add `ffmpeg_kit_flutter_min_gpl` dependency (Reverted)
- [x] Remove `ffmpeg_kit_flutter_min_gpl` dependency
- [x] Implement `_exportVideo` logic using `Process.run` and specific FFmpeg path
- [x] Implement "Lock Aspect Ratio" Toggle
- [x] Implement Transform Reset on Video Load
- [x] Initialize `ShowState` with Blank Project (New Show)
- [x] Implement Project Renaming in `ProjectTab`
- [x] Reorder Tabs (Project -> Setup -> Video)
- [x] Fix Export ignoring applied transforms
- [x] Separate Zoom and Crop modes in Edit UI
- [x] Rename Video Tab to "Videos / Effects"
- [x] Create `EffectService` (Painters + FFmpeg Logic)
- [x] Create `EffectRenderer` Widget
- [x] Integrate Effects into `VideoTab` (UI, State, Export)
- [x] Integrate Effects into `VideoTab` (UI, State, Export)
- [x] Enable Panning in View Mode
- [/] Verify Effect Tunability and Export

## Project Saving & Transfer
- [ ] Implement Thumbnail Generation (RepaintBoundary)
- [ ] Implement Show Bundling (Zip: manifest, media, thumb)
- [ ] Upgrade FileUploader to handle Bundle upload
- [ ] Create Transfer UI (Card form with Thumbnail & Player list)
- [x] Create Transfer UI (Card form with Thumbnail & Player list)
- [ ] Verify Saving and Transfer flow

## Validation & Persistence
- [x] Verify `ShowManifest` includes fixtures and transform data <!-- id: 12 -->
- [x] Implement UI Validation (Disable Save/Transfer if no video) <!-- id: 13 -->
- [x] Allow selecting discovered player to import Matrix Characteristics <!-- id: 15 -->
- [x] Ensure `ShowState` captures matrix configuration in `fixtures` <!-- id: 14 -->
