import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart'; // For PointerScrollEvent
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'; // For ByteData
import 'package:kinet_composer/ui/widgets/glass_container.dart';
import 'package:kinet_composer/ui/widgets/grid_background_painter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:path/path.dart' as p;
import 'package:kinet_composer/ui/widgets/stylized_color_picker.dart';
import 'package:provider/provider.dart';

import '../../models/show_manifest.dart';
import '../../models/media_transform.dart';
import '../../state/show_state.dart';
import '../../services/effect_service.dart';
import '../../services/ffmpeg_service.dart';
import '../../services/pixel_engine.dart';
import '../widgets/pixel_grid_painter.dart';
import '../widgets/transform_gizmo.dart';
import '../widgets/effect_renderer.dart';
import '../widgets/transfer_dialog.dart';
import '../widgets/layer_renderer.dart';
import '../../models/layer_config.dart';
import '../widgets/glass_container.dart';
import '../widgets/layer_controls.dart'; 
import '../dialogs/render_dialog.dart'; 

import 'package:vector_math/vector_math_64.dart' hide Colors;

class VideoTab extends StatefulWidget {
  const VideoTab({super.key});

  @override
  State<VideoTab> createState() => _VideoTabState();
}

class _VideoTabState extends State<VideoTab> {
  static const double kGridSize = 16.0;

  final TransformationController _zoomController = TransformationController(); // Added Zoom Controller
  Size? _lastViewportSize; // Track viewport for Fit View

  late final Player _bgPlayer;
  late final VideoController _bgController;
  late final Player _fgPlayer;
  late final VideoController _fgController;
  late final Player _mdPlayer;
  late final VideoController _mdController;

  
  String? _loadedBgPath;
  String? _loadedMdPath;
  String? _loadedFgPath;
  

  
  LayerTarget _selectedLayer = LayerTarget.foreground;
  
  // Handlers
  void _onMouseWheel(PointerSignalEvent event) {
      if (event is PointerScrollEvent) {
          double scaleFactor = 1.1;
          if (event.scrollDelta.dy > 0) {
            scaleFactor = 0.9; // Zoom Out
          }

      final double currentScale = _zoomController.value.getMaxScaleOnAxis();
      final double newScale = currentScale * scaleFactor;

      // Clamp Zoom (Min 0.05x, Max 10.0x)
      if (newScale < 0.05 || newScale > 10.0) return;

      final Offset focalPoint = event.localPosition;

      // Math to zoom around the focal point:
      // Translate to origin (focal point) -> Scale -> Translate back
      final Matrix4 transform = Matrix4.identity()
        ..translate(focalPoint.dx, focalPoint.dy)
        ..scale(scaleFactor)
        ..translate(-focalPoint.dx, -focalPoint.dy);

      setState(() {
        _zoomController.value = transform * _zoomController.value;
      });
      }
  }

  
  // REMOVED: bool _isEditingCrop = false;
  // REMOVED: MediaTransform? _tempTransform;
  
  // NEW: Intersection State for UI
  Rect? _currentIntersection;
  
  bool _isHoveringWorkspace = false; // NEW
  bool _isInteracting = false; // NEW
  
  int _intersectW = 0;
  int _intersectH = 0;
  int _displayX = 0;
  int _displayY = 0;

  late final StreamSubscription<bool> _playingSubscription;
  late final StreamSubscription<bool> _fgPlayingSubscription;
  late final StreamSubscription<bool> _mdPlayingSubscription;

  bool _pendingAutoFit = false;
  final List<StreamSubscription> _dimensionSubs = [];

  // NEW: Aspect Ratio Lock State
  // NEW: Aspect Ratio Lock State (Managed by LayerConfig now)
  // bool _lockAspectRatio = true; // REMOVED
  // REMOVED: EditMode _editMode = EditMode.zoom;

  // NEW: Effects State

  // REMOVED: Map<String, double> _effectParams = {};
  
  final GlobalKey _previewKey = GlobalKey(); // For Snapshot
  
  late final TextEditingController _nameController;

  


  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: "New Show"); // Will be updated by Provider listener or Load
    
    _bgPlayer = Player();
    _bgController = VideoController(_bgPlayer);

    _mdPlayer = Player();
    _mdController = VideoController(_mdPlayer);
    
    _fgPlayer = Player();
    _fgController = VideoController(_fgPlayer);
    
    // Unified Playing Listener
    // Note: We deliberately DO NOT listen to player state to drive _isPlaying.
    // This allows effects to keep "playing" (animating) even if video players stop.
    // _playingSubscription = _bgPlayer.stream.playing.listen(updatePlayingState);
    
    // Auto-Fit & Intersection Listeners (All Players)
    void addListeners(Player p) {
        _dimensionSubs.add(p.stream.width.listen((_) => _onDimensionsChanged()));
        _dimensionSubs.add(p.stream.height.listen((_) => _onDimensionsChanged()));
    }
    
    addListeners(_bgPlayer);
    addListeners(_mdPlayer);
    addListeners(_fgPlayer);
  }
  
  // Helper for Time Formatting
  String _formatTime(TimeOfDay t) {
      final hour = t.hour.toString().padLeft(2, '0');
      final minute = t.minute.toString().padLeft(2, '0');
      return "$hour:$minute";
  }

  Future<void> _pickTime(BuildContext context, TimeOfDay initial, Function(TimeOfDay) onSelected) async {
     final picked = await showTimePicker(
        context: context, 
        initialTime: initial,
        builder: (context, child) {
           return Theme(
              data: ThemeData.dark().copyWith(
                 colorScheme: const ColorScheme.dark(
                    primary: Colors.cyanAccent,
                    onPrimary: Colors.black, // Cyan is light, so use black text on top
                    surface: Color(0xFF1E1E1E), 
                    onSurface: Colors.white,
                 ),
                 dialogBackgroundColor: const Color(0xFF1E1E1E),
              ),
              child: child!,
           );
        }
     );
     if (picked != null) onSelected(picked);
  }
  
  void _onDimensionsChanged() {
    _checkAutoFit();
    _calculateIntersection();
  }

  void _checkAutoFit() {
     if (!_pendingAutoFit) return;
     
     // Determine active player
     final Player? activePlayer = switch(_selectedLayer) {
        LayerTarget.background => _bgPlayer,
        LayerTarget.middle => _mdPlayer,
        LayerTarget.foreground => _fgPlayer,
     };
     
     if (activePlayer == null) return;

     final w = activePlayer.state.width;
     final h = activePlayer.state.height;
     
     if (w != null && h != null && w > 0 && h > 0) {
        _performAutoFit(w, h, _selectedLayer);
        _pendingAutoFit = false;
     }
  }

  void _autoFitVideoToMatrix(int videoW, int videoH) {
     final show = context.read<ShowState>().currentShow;
     if (show == null || show.fixtures.isEmpty) return;
     
     // Only auto-fit if we are loading into the currently selected layer or force it?
     // Actually, this method is called by _bgPlayer stream. 
     // If we load FG, we need a separate listener for FG player!
     // But for now, let's just make sure it targets the correct layer if we assume this is triggered by "Load Video" on active layer.
     // But _checkAutoFit is ONLY listening to BG player (lines 96-97).
     // We need to listen to FG player too.
  }
  
  // Revised AutoFit that takes layer target
  void _performAutoFit(int w, int h, LayerTarget targetLayer) {
     final show = context.read<ShowState>().currentShow;
     if (show == null || show.fixtures.isEmpty) return;

     // 1. Calculate Matrix Bounds (Correctly)
     double minMx = double.infinity, maxMx = double.negativeInfinity;
     double minMy = double.infinity, maxMy = double.negativeInfinity;
     
     for (var f in show.fixtures) {
        for (var p in f.pixels) {
           double px = f.x + (p.x * kGridSize);
           double py = f.y + (p.y * kGridSize);
           if (px < minMx) minMx = px;
           if (px > maxMx) maxMx = px;
           if (py < minMy) minMy = py;
           if (py > maxMy) maxMy = py;
        }
     }
     maxMx += kGridSize; 
     maxMy += kGridSize;
     
     double matW = maxMx - minMx;
     double matH = maxMy - minMy;
     
     if (matW <= 0 || matH <= 0) return;

     // 2. Calculate Scale (Contain)
     double scaleX = matW / w;
     double scaleY = matH / h;
     double scale = (scaleX < scaleY) ? scaleX : scaleY; // Contain
     
     double cx = minMx + matW / 2.0;
     double cy = minMy + matH / 2.0;
     
     // 3. Apply
     WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ShowState>().updateLayer(
           target: targetLayer,
           transform: MediaTransform(
             scaleX: scale,
             scaleY: scale,
             translateX: cx - 1600.0,
             translateY: cy - 800.0,
             rotation: 0
          )
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("Auto-scaled ${targetLayer.name.toUpperCase()} to match matrix"), duration: const Duration(seconds: 1))
        );
        
        // Trigger intersection update here too for file loads
        _calculateIntersection();
     });
  }

  @override
  void dispose() {
    for (var sub in _dimensionSubs) sub.cancel();
    _bgPlayer.dispose();
    _mdPlayer.dispose();
    _fgPlayer.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // --- SHOW NAME UPDATE LOGIC ---
  Future<void> _pickVideo(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      dialogTitle: 'Select Video File (${_selectedLayer.name.toUpperCase()})',
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      if (context.mounted) {
         context.read<ShowState>().updateLayer(
            target: _selectedLayer,
            type: LayerType.video,
            path: path
         );
         
         // Force fit to matrix after loading
         WidgetsBinding.instance.addPostFrameCallback((_) {
             if (mounted) {
               context.read<ShowState>().updateLayer(target: _selectedLayer, lockAspectRatio: true);
               _fitToMatrix();
             }
         });
      }
    }
  }


  // Helper to resolve layer size (Video or Effect default)
  Size _resolveLayerSize(ShowManifest show, LayerConfig layer) {
     if (layer.type == LayerType.video) {
        if (layer == show.backgroundLayer) {
           return Size((_bgPlayer.state.width ?? 1920).toDouble(), (_bgPlayer.state.height ?? 1080).toDouble());
        } else if (layer == show.middleLayer) {
           return Size((_mdPlayer.state.width ?? 1920).toDouble(), (_mdPlayer.state.height ?? 1080).toDouble());
        } else {
           return Size((_fgPlayer.state.width ?? 1920).toDouble(), (_fgPlayer.state.height ?? 1080).toDouble());
        }
     }
     // Effects default to HD
     return const Size(1920, 1080);
  }

  Future<void> _exportEffect() async {
     final show = context.read<ShowState>().currentShow;
     if (show == null) return;

     final activeLayer = switch(_selectedLayer) {
        LayerTarget.background => show.backgroundLayer,
        LayerTarget.middle => show.middleLayer,
        LayerTarget.foreground => show.foregroundLayer,
     };

     if (activeLayer.type != LayerType.effect || activeLayer.effect == null) return;
     final effectType = activeLayer.effect!;

     final outputPath = await FilePicker.platform.saveFile(
       dialogTitle: 'Save Effect Video',
       fileName: 'effect_${effectType.name}.mp4',
       type: FileType.video,
       allowedExtensions: ['mp4'],
     );

     if (outputPath == null) return;
     if (!mounted) return;

     showDialog(
       context: context,
       barrierDismissible: false,
       builder: (c) => const AlertDialog(
         content: Column(
           mainAxisSize: MainAxisSize.min,
           children: [
             CircularProgressIndicator(),
             SizedBox(height: 20),
             Text("Generating Effect Video..."),
           ],
         ),
       ),
     );

     try {
        final filter = EffectService.getFFmpegFilter(
           effectType, 
           activeLayer.effectParams
        );
        // Use system ffmpeg
        const String ffmpegPath = 'ffmpeg';
        
        // Parse source to separate -i and -vf for robustness
        String source = "color=c=black:s=1920x1080";
        String? vf;
        
        if (filter.contains(',')) {
          final splitIndex = filter.indexOf(',');
          source = filter.substring(0, splitIndex);
          vf = filter.substring(splitIndex + 1);
        } else {
          source = filter;
        }

        List<String> args = [
           '-f', 'lavfi',
           '-i', source, 
           '-t', '10',
           '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-y', outputPath
        ];

        if (vf != null && vf.isNotEmpty) {
           // Insert before output options
           int insertIdx = args.indexOf('-c:v');
           if (insertIdx != -1) {
              args.insertAll(insertIdx, ['-vf', vf]);
           }
        }

        debugPrint("FFmpeg Effect: $ffmpegPath ${args.join(' ')}");
        final result = await Process.run(ffmpegPath, args);
        
        if (mounted) {
           Navigator.pop(context);
           if (result.exitCode == 0) {
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Effect Saved!")));
               context.read<ShowState>().updateMedia(outputPath);
           } else {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed: ${result.stderr}")));
           }
        }
     } catch (e) {
        if(mounted) Navigator.pop(context);
        debugPrint("Effect Export Error: $e");
     }
  }



  // --- THUMBNAIL GENERATION ---
  Future<File?> _captureThumbnail() async {
     try {
       RenderRepaintBoundary? boundary = _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
       if (boundary == null) return null;
       
       // Capture image
       ui.Image image = await boundary.toImage(pixelRatio: 0.5); // 0.5 for efficiency
       ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
       if (byteData == null) return null;
       
       // Save to temp
       final tempDir = await getTemporaryDirectory();
       final file = File('${tempDir.path}/thumbnail.png');
       await file.writeAsBytes(byteData.buffer.asUint8List());
       return file;
     } catch (e) {
       debugPrint("Thumbnail Error: $e");
       return null;
     }
  }



  // MARK: - Show Management
  
  Future<void> _saveShow() async {
      final show = context.read<ShowState>().currentShow;
      if (show == null) return;
      
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Show',
        fileName: '${show.name}.show',
        allowedExtensions: ['show', 'json'],
        type: FileType.custom,
      );
      
      if (outputPath != null) {
         try {
             // Ensure extension
             if (!outputPath.endsWith('.show') && !outputPath.endsWith('.json')) {
                 outputPath += ".show";
             }
             
             final jsonStr = jsonEncode(show.toJson());
             await File(outputPath).writeAsString(jsonStr);
             
             // Update Name in State and Controller
             final newName = p.basenameWithoutExtension(outputPath);
             context.read<ShowState>().updateName(newName);
             setState(() {
                _nameController.text = newName;
             });

             if (mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text("Show saved to $outputPath"), backgroundColor: Colors.green)
                 );
             }
         } catch (e) {
             debugPrint("Error saving show: $e");
              if (mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text("Failed to save: $e"), backgroundColor: Colors.red)
                 );
             }
         }
      }
  }

  Future<void> _loadShow() async {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
          dialogTitle: "Load Show",
          type: FileType.custom,
          allowedExtensions: ['show', 'json'],
      );
      
      if (result != null && result.files.single.path != null) {
          try {
            final file = File(result.files.single.path!);
            
            // Safer Read: Bytes -> String
            debugPrint("Using Binary Loader for ${file.path}");
            final bytes = await file.readAsBytes();
            String jsonStr;
            
            // Check BOM for UTF-16LE (FF FE)
            if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
               final codes = <int>[];
               for (int i = 2; i < bytes.length - 1; i += 2) {
                  codes.add(bytes[i] | (bytes[i + 1] << 8));
               }
               jsonStr = String.fromCharCodes(codes);
            } else {
               // Try UTF-8 first
               try {
                  jsonStr = utf8.decode(bytes);
               } catch (_) {
                  // Fallback to ASCII/Latin1
                  jsonStr = String.fromCharCodes(bytes);
               }
            }
            
            final dynamic jsonMap = jsonDecode(jsonStr);
            
            if (jsonMap is! Map<String, dynamic>) throw "Invalid Show File Format (Not a Map)";

            var newShow = ShowManifest.fromJson(jsonMap);
              
              // Force Name from Filename
              final filename = p.basenameWithoutExtension(file.path);
              newShow = newShow.copyWith(name: filename);
              
              if (mounted) {
                  // We need to reload players if paths changed, 
                  // but ShowState/LayerRenderer handling should potentially handle it?
                  // Currently LayerRenderer listens to show changes?
                  // No, LayerRenderer gets 'layer' passed.
                  // If we replace the Show in ShowState, the UI rebuilds.
                  // LayerRenderer init logic might need reset.
                  
                  // Force stop existing playback (Cleanup)
                  await _bgPlayer.stop();
                  await _mdPlayer.stop();
                  await _fgPlayer.stop();
                  
                  _loadedBgPath = null;
                  _loadedMdPath = null;
                  _loadedFgPath = null;
                  
                  // CALCULATE STATE BEFORE LOADING
                  // valid content check
                  bool hasBg = newShow.backgroundLayer.type != LayerType.none;
                  bool hasMd = newShow.middleLayer.type != LayerType.none;
                  bool hasFg = newShow.foregroundLayer.type != LayerType.none;
                  bool hasContent = hasBg || hasMd || hasFg;
                  
                  debugPrint("DEBUG_LOAD: hasContent=$hasContent | BG: ${newShow.backgroundLayer.type} | MD: ${newShow.middleLayer.type} | FG: ${newShow.foregroundLayer.type}");

                  // UPDATE UI STATE FIRST
                  setState(() {
                      context.read<ShowState>().setPlaying(hasContent);
                      
                      _nameController.text = newShow.name;

                      // Auto-select the top-most active layer
                      if (hasFg) {
                         _selectedLayer = LayerTarget.foreground;
                      } else if (hasMd) {
                         _selectedLayer = LayerTarget.middle;
                      } else if (hasBg) {
                         _selectedLayer = LayerTarget.background;
                      }
                  });
                  
                  // NOW LOAD MANIFEST (Triggers Build with Correct State)
                  context.read<ShowState>().loadManifest(newShow);
                  
                  // Trigger Sync to actually start playback if IsPlaying is true
                  _syncLayers(newShow);
                  
                  // Force intersection update for the new show's transforms
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                         _calculateIntersection();
                         
                         // IMMEDIATE FORCE
                         if (hasContent) {
                            context.read<ShowState>().setPlaying(true);
                         }

                         // DELAYED ENFORCEMENT (The "Sledgehammer")
                         // Waits for player streams to settle, then forces Play again.
                         Future.delayed(const Duration(milliseconds: 500), () {
                            if (mounted && hasContent) {
                               debugPrint("DEBUG_LOAD: Sledgehammer Playback Enforcement");
                               context.read<ShowState>().setPlaying(true);
                               
                               if (_loadedBgPath != null) { _bgPlayer.play(); _bgPlayer.setPlaylistMode(PlaylistMode.loop); }
                               if (_loadedMdPath != null) { _mdPlayer.play(); _mdPlayer.setPlaylistMode(PlaylistMode.loop); }
                               if (_loadedFgPath != null) { _fgPlayer.play(); _fgPlayer.setPlaylistMode(PlaylistMode.loop); }
                            }
                         });
                      }
                  });

                   String debugMsg = "Show Loaded. Content=${hasContent ? 'Yes' : 'No'} (B:${newShow.backgroundLayer.type.name}, M:${newShow.middleLayer.type.name}, F:${newShow.foregroundLayer.type.name}).";
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(
                        content: Text(debugMsg), 
                        backgroundColor: hasContent ? Colors.green : Colors.orange,
                        duration: const Duration(seconds: 5),
                     )
                 );
              }
          } catch (e) {
              debugPrint("Error loading show: $e");
              if (mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text("Failed to load: $e"), backgroundColor: Colors.red)
                 );
             }
          }
      }
  }

  void _initializeShow() {
      showDialog(
        context: context, 
        builder: (c) => AlertDialog(
          title: const Text("Initialize Show?"),
          content: const Text("This will clear all layers and reset settings. Are you sure?"),
          actions: [
            TextButton(
               onPressed: () => Navigator.pop(context),
               child: const Text("Cancel"),
            ),
             TextButton(
               onPressed: () {
                 Navigator.pop(context);
                 _performInitialize();
               },
               child: const Text("Initialize", style: TextStyle(color: Colors.red)),
            ),
          ]
        )
      );
  }
  
  void _performInitialize() {
      _bgPlayer.stop();
      _mdPlayer.stop();
      _fgPlayer.stop();
      
      setState(() {
         // _isPlaying = false; // Moved to Provider
         context.read<ShowState>().setPlaying(false);
         _loadedBgPath = null;
         _loadedMdPath = null;
         _loadedFgPath = null;
         _nameController.text = "New Show";
      });
      
      final state = context.read<ShowState>();
      state.updateLayer(target: LayerTarget.background, type: LayerType.none, path: null, effect: null, lockAspectRatio: true, opacity: 1.0, transform: MediaTransform.identity());
      state.updateLayer(target: LayerTarget.middle, type: LayerType.none, path: null, effect: null, lockAspectRatio: true, opacity: 1.0, transform: MediaTransform.identity());
      state.updateLayer(target: LayerTarget.foreground, type: LayerType.none, path: null, effect: null, lockAspectRatio: true, opacity: 1.0, transform: MediaTransform.identity());
      
      // Clear intersection
      _calculateIntersection();
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Show Initialized")));
  }

  Future<void> _renderVideo() async {
      final players = {
         LayerTarget.background: _bgPlayer,
         LayerTarget.middle: _mdPlayer,
         LayerTarget.foreground: _fgPlayer,
      };

      // Auto-pause before render
      if (context.read<ShowState>().isPlaying) {
         _bgPlayer.pause();
         _mdPlayer.pause();
         _fgPlayer.pause();
         context.read<ShowState>().setPlaying(false);
      }
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => RenderDialog(
           repaintBoundaryKey: _previewKey,
           players: players,
        ),
      );
  }

  Widget _buildIconFn(IconData icon, String label, Color color, VoidCallback? onTap) {
      bool isEnabled = onTap != null;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: isEnabled ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.02),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isEnabled ? color.withOpacity(0.3) : Colors.transparent),
            ),
            child: Column(
               children: [
                 Icon(icon, color: isEnabled ? color : Colors.white24, size: 20),
                 const SizedBox(height: 4),
                 Text(label, style: TextStyle(color: isEnabled ? Colors.white70 : Colors.white24, fontSize: 10, fontWeight: FontWeight.bold)),
               ],
            ),
          ),
        ),
      );
  }

  Future<void> _exportVideo() async {
     
     // Need FfmpegService
     final show = context.read<ShowState>().currentShow;
     if (show == null) return;

     // Check if we have background/any layer
     if (show.backgroundLayer.type == LayerType.none && show.middleLayer.type == LayerType.none && show.foregroundLayer.type == LayerType.none) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No content to render!")));
         return;
     }

    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Rendered Video',
      fileName: 'composite_render.mp4',
      type: FileType.video,
      allowedExtensions: ['mp4'],
    );

    if (outputPath == null) return;
    if (!mounted) return;

    // Show Progress Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text("Rendering Composite Video..."),
            Text("Please wait, this may take a moment.", style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );

    try {
       // Get Video Sizes
       final bgSize = Size((_bgPlayer.state.width ?? 1920).toDouble(), (_bgPlayer.state.height ?? 1080).toDouble());
       final mdSize = Size((_mdPlayer.state.width ?? 1920).toDouble(), (_mdPlayer.state.height ?? 1080).toDouble());
       final fgSize = Size((_fgPlayer.state.width ?? 1920).toDouble(), (_fgPlayer.state.height ?? 1080).toDouble()); // Corrected FG Size

       // Execute Render
       // 1. Calculate Full Matrix Bounds (Global Logic Space)
       double minMx = double.infinity, maxMx = double.negativeInfinity;
       double minMy = double.infinity, maxMy = double.negativeInfinity;
       
       if (show.fixtures.isEmpty) {
           throw Exception("No Fixtures defined! Cannot determine output resolution.");
       }

       for (var f in show.fixtures) {
          for (var p in f.pixels) {
              double px = f.x + (p.x * kGridSize);
              double py = f.y + (p.y * kGridSize);
              if (px < minMx) minMx = px;
              if (px > maxMx) maxMx = px;
              if (py < minMy) minMy = py;
              if (py > maxMy) maxMy = py;
          }
       }
       maxMx += kGridSize; 
       maxMy += kGridSize;
       
       double matW = maxMx - minMx;
       double matH = maxMy - minMy;
       
       // 2. Define Canvas Rect (centered at 0,0 relative to world, but we need Global Coords)
       // The matrix pixels are in Global Logic Space.
       // The matrixRect should be the bounding box of all pixels.
       Rect matrixRect = Rect.fromLTRB(minMx, minMy, maxMx, maxMy);
       
       // 3. Define Resolution
       int resW = (matW / kGridSize).round();
       int resH = (matH / kGridSize).round();

       debugPrint("Render Target: $resW x $resH (Logic: ${matrixRect.toString()})");

       final result = await FfmpegService.renderShow(
          show: show,
          intersection: matrixRect,
          resW: resW,
          resH: resH,
          outputPath: outputPath,
          bgVideoSize: bgSize,
          mdVideoSize: mdSize,
          fgVideoSize: fgSize,
       );

       if (mounted) {
          Navigator.pop(context); // Hide Dialog
          
          if (result.exitCode == 0) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Render Successful!"), backgroundColor: Colors.green));
              // Update media to cached result?
              // context.read<ShowState>().updateMedia(outputPath); // Optional
          } else {
             _showErrorDialog("Render Failed (Exit ${result.exitCode})", result.stderr.toString());
          }
       }
    } catch (e) {
       if (mounted) {
         Navigator.pop(context);
         _showErrorDialog("Render Error", e.toString());
       }
    }
  }

  void _showErrorDialog(String title, String message) {
     showDialog(
       context: context,
       builder: (c) => AlertDialog(
         title: Text(title),
         content: SingleChildScrollView(child: Text(message)),
         actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("OK"))],
       )
     );
  }




  void _fitToMatrix() {
    debugPrint("Auto-Fit: Clicked (Camera Mode)");
    final show = context.read<ShowState>().currentShow;
    
    // We need viewport size to calculate fit
    if (_lastViewportSize == null) {
       debugPrint("Auto-Fit: Aborted (No Viewport Size)");
       return;
    }
    
    if (show == null || show.fixtures.isEmpty) {
       debugPrint("Auto-Fit: Aborted (No Fixtures)");
       return;
    }

    // 1. Calculate Matrix Bounds in "Pixel" space (3200x1600 Canvas Space)
    final bounds = _calculateMatrixBounds(show);
    
    if (bounds.width <= 0 || bounds.height <= 0) {
       debugPrint("Auto-Fit: Aborted (Invalid Bounds)");
       return;
    }
    
    // 2. Calculate Required Scale
    // We want 'bounds' to fit into '_lastViewportSize' with some padding
    final padding = 50.0;
    final viewW = _lastViewportSize!.width - (padding * 2);
    final viewH = _lastViewportSize!.height - (padding * 2);
    
    double scaleX = viewW / bounds.width;
    double scaleY = viewH / bounds.height;
    double scale = min(scaleX, scaleY); // Contain
    
    // Clamp Scale (Optional, but good for sanity)
    scale = scale.clamp(0.1, 10.0);
    
    debugPrint("Auto-Fit: Bounds=${bounds.width}x${bounds.height} View=${viewW}x${viewH} => Scale=$scale");

    // 3. Calculate Translation
    // We want the Center of Bounds (Cx, Cy) to align with Center of Viewport (Vx, Vy)
    // Formula: V = S * C + T  =>  T = V - S * C
    
    final viewCenter = Offset(_lastViewportSize!.width / 2.0, _lastViewportSize!.height / 2.0);
    final boundsCenter = bounds.center;
    
    // However, InteractiveViewer's coordinate system origin is Top-Left of the *Child*.
    // The child is the 3200x1600 container.
    // 'bounds' is ALREADY in the child's coordinate space.
    // So 'boundsCenter' is correct relative to the child origin.
    
    final tx = viewCenter.dx - (boundsCenter.dx * scale);
    final ty = viewCenter.dy - (boundsCenter.dy * scale);
    
    debugPrint("Auto-Fit: Target Matrix T($tx, $ty) S($scale)");

    // 4. Apply to Controller
    final matrix = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);
      
    // Animate? TransformationController doesn't animate natively.
    // We'll set it directly for responsiveness.
    _zoomController.value = matrix;
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Auto-Fit: Camera Adjusted"), duration: Duration(milliseconds: 500)));
  }

  void _syncLayers(ShowManifest show) {
    // Background
    final bgLayer = show.backgroundLayer;
    if (bgLayer.type != LayerType.video) {
        if (_bgPlayer.state.playing) _bgPlayer.stop();
        _loadedBgPath = null; // Force reload if switching back to video
    } else {
        final bgPath = bgLayer.path;
        if (bgPath != _loadedBgPath) {
          if (bgPath != null && bgPath.isNotEmpty) {
             _bgPlayer.open(Media(bgPath), play: true);
             _bgPlayer.setPlaylistMode(PlaylistMode.loop);
             // Auto-Fit if fresh load
             if (show.backgroundLayer.transform == null) _autoFitVideo(LayerTarget.background, _bgPlayer);
          } else {
             _bgPlayer.stop();
          }
          _loadedBgPath = bgPath;
        }
    }

    // Middle
    final mdLayer = show.middleLayer;
    if (mdLayer.type != LayerType.video) {
        if (_mdPlayer.state.playing) _mdPlayer.stop();
        _loadedMdPath = null;
    } else {
        final mdPath = mdLayer.path;
        if (mdPath != _loadedMdPath) {
          if (mdPath != null && mdPath.isNotEmpty) {
             _mdPlayer.open(Media(mdPath), play: true);
             _mdPlayer.setPlaylistMode(PlaylistMode.loop);
             if (show.middleLayer.transform == null) _autoFitVideo(LayerTarget.middle, _mdPlayer);
          } else {
             _mdPlayer.stop();
          }
          _loadedMdPath = mdPath;
        }
    }

    // Foreground
    final fgLayer = show.foregroundLayer;
    if (fgLayer.type != LayerType.video) {
        if (_fgPlayer.state.playing) _fgPlayer.stop();
        _loadedFgPath = null;
    } else {
        final fgPath = fgLayer.path;
        if (fgPath != _loadedFgPath) {
          if (fgPath != null && fgPath.isNotEmpty) {
             _fgPlayer.open(Media(fgPath), play: true);
             _fgPlayer.setPlaylistMode(PlaylistMode.loop);
             if (show.foregroundLayer.transform == null) _autoFitVideo(LayerTarget.foreground, _fgPlayer);
          } else {
             _fgPlayer.stop();
          }
          _loadedFgPath = fgPath;
        }
    }

    
    // Force Sync Playback State
    // If the global state is playing, ensure any active video players are playing.
    if (context.read<ShowState>().isPlaying) {
       if (_bgPlayer.state.playing == false && _loadedBgPath != null) _bgPlayer.play();
       if (_mdPlayer.state.playing == false && _loadedMdPath != null) _mdPlayer.play();
       if (_fgPlayer.state.playing == false && _loadedFgPath != null) _fgPlayer.play();
    } else {
       // Using fire-and-forget; avoid awaiting to keep UI responsive
       if (_bgPlayer.state.playing) _bgPlayer.pause();
       if (_mdPlayer.state.playing) _mdPlayer.pause();
       if (_fgPlayer.state.playing) _fgPlayer.pause();
    }
  }
  


  void _autoFitVideo(LayerTarget target, Player player) {
     StreamSubscription? sub;
     debugPrint("Auto-Fit: Starting for $target");
     sub = player.stream.videoParams.listen((params) {
        debugPrint("Auto-Fit: Params received $target w=${params.w} h=${params.h}");
        if (params.w != null && params.h != null && params.w! > 0 && params.h! > 0) {
           if (!mounted) { sub?.cancel(); return; }
           
           final show = context.read<ShowState>().currentShow;
           if (show == null) { sub?.cancel(); return; }
           
           final bounds = _calculateMatrixBounds(show);
           double matW = bounds.width;
           double matH = bounds.height;
           
           // GUARD: If Matrix Bounds are suspicious (e.g. 0 implies no real pixels), don't auto-fit yet.
           // A real matrix (1 pixel * 10 grid) should be >= 10. 
           // We only abort if it's effectively empty (<= 0).
           if (bounds.width <= 0) { 
               debugPrint("Auto-Fit: Skipped. Matrix bounds invalid (${bounds.width}). Waiting for valid fixtures.");
               sub?.cancel(); 
               return; 
           }
           
           // Safe Fallback
           if (matW <= 0) matW = 3000;
           if (matH <= 0) matH = 2000;
           
           double scaleX = matW / params.w!;
           double scaleY = matH / params.h!;
           
           debugPrint("Auto-Fit: Matrix=${matW}x$matH Video=${params.w}x${params.h} => Scale ${scaleX.toStringAsFixed(3)}");

           // Apply Stretch Transform
           context.read<ShowState>().updateLayer(
              target: target,
              transform: MediaTransform(
                 scaleX: scaleX,
                 scaleY: scaleY,
                 translateX: 0, 
                 translateY: 0,
                 rotation: 0
              ),
              lockAspectRatio: false // Unlock aspect for full stretch
           );
           
           sub?.cancel();
        }
     });
  }
  
  Rect _calculateMatrixBounds(ShowManifest show) {
     if (show.fixtures.isEmpty) return const Rect.fromLTWH(0, 0, 0, 0);
     // 1. Calculate Matrix Bounds (Robust)
     double minMx = double.infinity, maxMx = double.negativeInfinity;
     double minMy = double.infinity, maxMy = double.negativeInfinity;

     // Guard against empty fixtures
     if (show.fixtures.isEmpty) {
        // This method is called from _autoFitVideo, which already checks for bounds.width <= 0.
        // However, _calculateIntersection also calls this, and needs to update state.
        // This setState is only relevant if called from _calculateIntersection.
        // For _autoFitVideo, the return Rect.fromLTWH(0,0,0,0) will trigger the skip logic.
        if (mounted) { // Only call setState if widget is mounted
           setState(() {
              _currentIntersection = null; 
              _displayX = 0; _displayY = 0; _intersectW = 0; _intersectH = 0;
           });
        }
        return const Rect.fromLTWH(0, 0, 0, 0);
     }

     for (var f in show.fixtures) {
         double fw = f.width * kGridSize;
         double fh = f.height * kGridSize;

         
         double cx = fw / 2.0;
         double cy = fh / 2.0;
         
         // Fixture Corners (Local, Unrotated)
         List<Offset> corners = [
            const Offset(0, 0),
            Offset(fw, 0),
            Offset(0, fh),
            Offset(fw, fh),
         ];
         
         double rads = f.rotation * pi / 180.0;
         double c = (f.rotation == 0) ? 1.0 : cos(rads);
         double s = (f.rotation == 0) ? 0.0 : sin(rads);
         
         for (var point in corners) {
            // 1. Shift to Center (Pivot)
            double dx = point.dx - cx;
            double dy = point.dy - cy;
            
            // 2. Rotate
            double rx = dx * c - dy * s;
            double ry = dx * s + dy * c;
            
            // 3. Shift back + Global Offset (f.x, f.y)
            double finalX = rx + cx + f.x;
            double finalY = ry + cy + f.y;
            
            if (finalX < minMx) minMx = finalX;
            if (finalX > maxMx) maxMx = finalX;
            if (finalY < minMy) minMy = finalY;
            if (finalY > maxMy) maxMy = finalY;
         }
     }
     
     // If no valid bounds found (e.g. fixtures at infinity?), abort
     if (minMx == double.infinity) {
        if (mounted) { // Only call setState if widget is mounted
           setState(() => _currentIntersection = null);
        }
        return const Rect.fromLTWH(0, 0, 0, 0);
     }
     
     return Rect.fromLTRB(minMx, minMy, maxMx, maxMy);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ShowState>(
      builder: (context, showState, child) {
        final show = showState.currentShow;
        if (show == null) {
          return const Center(child: Text("Create or Load a Show first"));
        }

        _syncLayers(show);
        _syncPixelEngine(show);


        
        // Define active layer helper variables for UI
        final activeLayer = switch(_selectedLayer) {
           LayerTarget.background => show.backgroundLayer,
           LayerTarget.middle => show.middleLayer,
           LayerTarget.foreground => show.foregroundLayer,
        };
        final activeParams = activeLayer.effectParams;

        Size _getLayerSize(LayerConfig layer) {
            return _resolveLayerSize(show, layer);
        }

          return Stack(
            children: [
             Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
               // 1. Sidebar (Black & Square)
               Container(
                 width: 320,
                 color: Colors.black,
                 child: Container(
                    decoration: const BoxDecoration(
                      border: Border(right: BorderSide(color: Colors.white12)),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [

                         // 1. Show Name Header
                         // Show Name Header Removed (Moved to Global AppBar)
                         
                         // 2. File Actions
                         // Show Actions Removed
                         const SizedBox(height: 8),
                         Row(
                           children: [
                              Expanded(child: _buildIconFn(
                                 Icons.video_library, 
                                 "Load Video", 
                                 show.fixtures.isNotEmpty ? const Color(0xFF90CAF9) : Colors.white24, 
                                 show.fixtures.isNotEmpty ? () => _pickVideo(context) : null
                              )),
                              const SizedBox(width: 8),
                              Expanded(child: _buildIconFn(
                                 Icons.movie_creation, 
                                 "Render", 
                                 (show.fixtures.isNotEmpty && (show.backgroundLayer.type != LayerType.none || show.middleLayer.type != LayerType.none || show.foregroundLayer.type != LayerType.none))
                                 ? const Color(0xFFA5D6A7) : Colors.white24, 
                                 (show.fixtures.isNotEmpty && (show.backgroundLayer.type != LayerType.none || show.middleLayer.type != LayerType.none || show.foregroundLayer.type != LayerType.none))
                                 ? () => _renderVideo() : null
                              )),
                           ],
                         ),
                         const SizedBox(height: 8), 
                         // Init Show Removed
                         const SizedBox(height: 12),
                         // Pixel Mapping Switch
                         // Pixel Mapping Switch (Disabled if no grid)
                         Opacity(
                           opacity: show.fixtures.isNotEmpty ? 1.0 : 0.4,
                           child: IgnorePointer(
                             ignoring: show.fixtures.isEmpty,
                             child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                   color: Colors.white.withOpacity(0.05),
                                   borderRadius: BorderRadius.circular(8), // Fixed syntax: added missing comma or removed weird spacing? No, just ensuring clean replacement.
                                   border: Border.all(color: showState.isPixelMappingEnabled ? Colors.green.withOpacity(0.5) : Colors.transparent)
                                ),
                                child: Row(
                                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                               children: [
                                  Row(
                                    children: [
                                      Icon(Icons.hub, size: 16, color: showState.isPixelMappingEnabled ? Colors.greenAccent : Colors.white54),
                                      const SizedBox(width: 8),
                                      const Text("Pixel Mapping", style: TextStyle(color: Colors.white70, fontSize: 12)),
                                      const SizedBox(width: 8),
                                      // Overload Indicator
                                      ValueListenableBuilder<bool>(
                                         valueListenable: context.read<PixelEngine>().overloadWarning,
                                         builder: (ctx, isOverloaded, _) {
                                            if (!isOverloaded || !showState.isPixelMappingEnabled) return const SizedBox();
                                            return Tooltip(
                                               message: "System Overloaded (Dropping Frames)",
                                               child: Container(
                                                  width: 8, height: 8,
                                                  decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle)
                                               ),
                                            );
                                         }
                                      ),
                                    ],
                                  ),
                                  Transform.scale(
                                    scale: 0.7,
                                    child: Switch(
                                       value: showState.isPixelMappingEnabled,
                                       onChanged: (val) => context.read<ShowState>().setPixelMapping(val),
                                       activeColor: Colors.greenAccent,
                                       activeTrackColor: Colors.green.withOpacity(0.3),
                                       inactiveThumbColor: Colors.white24,
                                       inactiveTrackColor: Colors.white10,
                                    ),
                                  ),
                               ],
                            ),
                          ),
                        ),
                      ),
                         const SizedBox(height: 12),
  
                         // 3. Layer Controls
                         // REMOVED: Text("LAYERS")
                         const SizedBox(height: 12),

                        Opacity(
                          opacity: show.fixtures.isNotEmpty ? 1.0 : 0.4,
                          child: IgnorePointer(
                            ignoring: show.fixtures.isEmpty,
                            child: Row(
                               children: [
                                   // Play/Pause
                              Expanded(
                                child: Tooltip(
                                  message: showState.isPlaying ? "Pause" : "Play",
                                  child: InkWell(
                                    onTap: show.fixtures.isNotEmpty ? () {
                                       if (showState.isPlaying) {
                                         _bgPlayer.pause(); _mdPlayer.pause(); _fgPlayer.pause();
                                       } else {
                                         _bgPlayer.play(); _mdPlayer.play(); _fgPlayer.play();
                                       }
                                       context.read<ShowState>().setPlaying(!showState.isPlaying);
                                    } : null,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(color: show.fixtures.isNotEmpty ? Colors.white10 : Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(8)),
                                      child: Icon(showState.isPlaying ? Icons.pause : Icons.play_arrow, color: show.fixtures.isNotEmpty ? Colors.white70 : Colors.white24),
                                    ),
                                  ),
                                ),
                              ),

                             const SizedBox(width: 8),
                             // Aspect Ratio Lock
                             Expanded(
                               child: Tooltip(
                                 message: activeLayer.lockAspectRatio ? "Unlock Aspect Ratio" : "Lock Aspect Ratio",
                                 child: InkWell(
                                   onTap: (show.fixtures.isNotEmpty && activeLayer.type == LayerType.video) ? () {
                                      context.read<ShowState>().updateLayer(
                                        target: _selectedLayer,
                                        lockAspectRatio: !activeLayer.lockAspectRatio
                                      );
                                   } : null,
                                   child: Container(
                                     padding: const EdgeInsets.symmetric(vertical: 12),
                                     decoration: BoxDecoration(
                                       color: (show.fixtures.isNotEmpty && activeLayer.lockAspectRatio && activeLayer.type == LayerType.video) ? const Color(0xFF1565C0) : (show.fixtures.isNotEmpty ? Colors.white10 : Colors.white.withOpacity(0.02)), 
                                       borderRadius: BorderRadius.circular(8),
                                       border: Border.all(color: activeLayer.type == LayerType.video ? Colors.transparent : Colors.transparent)
                                     ),
                                     child: Icon(
                                       activeLayer.lockAspectRatio ? Icons.lock : Icons.lock_open, 
                                       color: show.fixtures.isNotEmpty ? (activeLayer.type == LayerType.video ? (activeLayer.lockAspectRatio ? Colors.white : Colors.white54) : Colors.white24) : Colors.white24,
                                       size: 20
                                     ),
                                   ),
                                 ),
                               ),
                             ),
                             const SizedBox(width: 8),
                             Expanded(
                               child: Tooltip(
                                 message: "Fit View",
                                 child: InkWell(
                                   onTap: show.fixtures.isNotEmpty ? () => _fitToMatrix() : null,
                                   child: Container(
                                     padding: const EdgeInsets.symmetric(vertical: 12),
                                     decoration: BoxDecoration(color: show.fixtures.isNotEmpty ? Colors.white10 : Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(8)),
                                     child: Icon(Icons.fit_screen, color: show.fixtures.isNotEmpty ? Colors.white70 : Colors.white24, size: 20),
                                   ),
                                 ),
                               ),
                             ),
                           ],
                        ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // SCHEDULER SECTION
                        Opacity(
                           opacity: show.fixtures.isNotEmpty ? 1.0 : 0.4,
                           child: IgnorePointer(
                              ignoring: show.fixtures.isEmpty,
                              child: _buildSchedulerSection(showState),
                           )
                        ),
                        const SizedBox(height: 24),

                       Opacity(
                         opacity: show.fixtures.isNotEmpty ? 1.0 : 0.4,
                         child: IgnorePointer(
                           ignoring: show.fixtures.isEmpty,
                           child: LayerControls(
                             selectedLayer: _selectedLayer,
                           onSelectLayer: (target) {
                              final show = context.read<ShowState>().currentShow;
                              if (show != null) {
                                 LayerConfig nextLayer = switch(target) {
                                    LayerTarget.background => show.backgroundLayer,
                                    LayerTarget.middle => show.middleLayer,
                                    LayerTarget.foreground => show.foregroundLayer,
                                 };
                                 
                                 setState(() {
                                    _selectedLayer = target;

                                    _calculateIntersection();
                                 });
                              }
                           },
                         ),
                       ),
                     ),
                         const SizedBox(height: 24),

                        const Divider(color: Colors.white10, height: 1),
                        const SizedBox(height: 24),



                        // 6. Effects
                        // 6. Effects
                        if (_hasActiveSelection && activeLayer.type == LayerType.effect && activeLayer.effect != null) ...[
                             // Effect Name Header (No Buttons)
                              Row(
                               key: ValueKey("EffectSettingsHeader_${activeLayer.effect}"),
                               children: [
                                  Expanded(
                                    child: Text(
                                      activeLayer.effect!.name.toUpperCase(), 
                                      style: const TextStyle(color: Color(0xFFA5D6A7), fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.white54, size: 16),
                                    tooltip: 'Remove Effect',
                                    onPressed: () {
                                      // Reset to None using Provider
                                      context.read<ShowState>().updateLayer(
                                        target: _selectedLayer,
                                        type: LayerType.none,
                                      );
                                    },
                                  ),
                               ],
                             ),
                             const SizedBox(height: 12),
                              
                            // Parameter Editor
                            Column(
                                key: ValueKey("EffectParams_${_selectedLayer}_${activeLayer.effect}"),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    ...activeLayer.effectParams.entries.map((entry) {
                                       final key = entry.key;
                                       dynamic value = entry.value;

                                       // Special Case: 'transparent' switch
                                       // User wants this to be a visible switch on the main list
                                       // Logic: If 'bgColor' exists, we hoist this switch to appear UNDER bgColor.
                                       // So if we are currently at 'transparent' key, AND 'bgColor' exists, we SKIP (return shrink).
                                       // If 'bgColor' does NOT exist (e.g. Matrix?), we render it here.
                                       if (key == 'transparent') {
                                          if (activeLayer.effectParams.containsKey('bgColor')) {
                                             return const SizedBox.shrink(); // Handled by bgColor logic
                                          }
                                          
                                          // Render normally if no bgColor
                                          bool isTransparent = (value as num).toDouble() >= 0.5;
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 12.0),
                                            child: Row(
                                               mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                               children: [
                                                  const Text("BACKGROUND TRANSPARENCY", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                                                  Transform.scale(
                                                    scale: 0.7,
                                                    child: Switch(
                                                       value: isTransparent,
                                                       onChanged: (val) {
                                                          final newParams = Map<String, dynamic>.from(activeLayer.effectParams);
                                                          newParams[key] = val ? 1.0 : 0.0;
                                                          context.read<ShowState>().updateLayer(
                                                             target: _selectedLayer, 
                                                             params: newParams
                                                          );
                                                       },
                                                       activeColor: Colors.greenAccent,
                                                       activeTrackColor: Colors.green.withOpacity(0.3),
                                                       inactiveThumbColor: Colors.white24,
                                                       inactiveTrackColor: Colors.white10,
                                                    ),
                                                  ),
                                               ],
                                            ),
                                          );
                                       }

                                       return Padding(
                                         padding: const EdgeInsets.only(bottom: 12.0),
                                         child: Column(
                                           crossAxisAlignment: CrossAxisAlignment.start,
                                           children: [
                                             // Label (Unless it's Color, which we handle as Row)
                                             if (!key.toLowerCase().contains('color') || !(value is int))
                                                Text(key.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                                             
                                             if (!key.toLowerCase().contains('color') || !(value is int))
                                                const SizedBox(height: 4),
                                             
                                             // 1. Color Picker (Horizontal Row Layout)
                                             if (key.toLowerCase().contains('color') && (value is int)) ...[
                                                 Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                       Text(key.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                                                       
                                                       GestureDetector(
                                                         onTap: () {
                                                            showDialog(
                                                              context: context,
                                                              builder: (c) {
                                                                 return StatefulBuilder(
                                                                   builder: (context, setStateDialog) {
                                                                      return AlertDialog(
                                                                        backgroundColor: const Color(0xFF222222),
                                                                        title: const Text("Pick Color", style: TextStyle(color: Colors.white)),
                                                                        content: Column(
                                                                           mainAxisSize: MainAxisSize.min,
                                                                           children: [
                                                                              StylizedColorPicker(
                                                                                pickerColor: Color(value),
                                                                                onColorChanged: (c) {
                                                                                   final newParams = Map<String, dynamic>.from(activeLayer.effectParams);
                                                                                   newParams[key] = c.value;
                                                                                   context.read<ShowState>().updateLayer(
                                                                                      target: _selectedLayer, 
                                                                                      params: newParams
                                                                                   );
                                                                                   value = c.value; 
                                                                                }
                                                                              ),
                                                                           ],
                                                                        ),
                                                                        actions: [
                                                                          TextButton(
                                                                             onPressed: () => Navigator.pop(c), 
                                                                             child: const Text("Done", style: TextStyle(color: Colors.blueAccent))
                                                                          )
                                                                        ],
                                                                      );
                                                                   }
                                                                 );
                                                              }
                                                            );
                                                         },
                                                         child: Container(
                                                           width: 60, // Compact width
                                                           height: 24, // Compact height
                                                           decoration: BoxDecoration(
                                                             color: Color(value),
                                                             borderRadius: BorderRadius.circular(4),
                                                             border: Border.all(color: Colors.white24)
                                                           ),
                                                         ),
                                                       )
                                                    ],
                                                 ),
                                                 
                                                 // HOISTED TRANSPARENCY SWITCH
                                                 // If this is bgColor, and we have a 'transparent' param, render it here directly below.
                                                 if (key == 'bgColor' && activeLayer.effectParams.containsKey('transparent')) ...[
                                                    const SizedBox(height: 12),
                                                    Builder(
                                                      builder: (context) {
                                                         final tKey = 'transparent';
                                                         double tVal = (activeLayer.effectParams[tKey] as num?)?.toDouble() ?? 0.0;
                                                         bool isTrans = tVal >= 0.5;
                                                         
                                                         return Row(
                                                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                           children: [
                                                              const Text("BACKGROUND TRANSPARENCY", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                                                              Transform.scale(
                                                                scale: 0.7,
                                                                child: Switch(
                                                                   value: isTrans,
                                                                   onChanged: (val) {
                                                                      final newParams = Map<String, dynamic>.from(activeLayer.effectParams);
                                                                      newParams[tKey] = val ? 1.0 : 0.0;
                                                                      context.read<ShowState>().updateLayer(
                                                                         target: _selectedLayer, 
                                                                         params: newParams
                                                                      );
                                                                   },
                                                                   activeColor: Colors.greenAccent,
                                                                   activeTrackColor: Colors.green.withOpacity(0.3),
                                                                   inactiveThumbColor: Colors.white24,
                                                                   inactiveTrackColor: Colors.white10,
                                                                ),
                                                              ),
                                                           ],
                                                         );
                                                      }
                                                    ),
                                                 ]
                                             
                                             // 2. Font Dropdown
                                             ] else if (key == 'font' && value is String) ...[
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white10,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: DropdownButtonHideUnderline(
                                                    child: DropdownButton<String>(
                                                      value: value,
                                                      isExpanded: true,
                                                      dropdownColor: const Color(0xFF1E1E1E),
                                                      style: const TextStyle(color: Colors.white, fontSize: 13),
                                                      items: const [
                                                        'Roboto', 
                                                        'Arial', 
                                                        'Courier New', 
                                                        'Times New Roman', 
                                                        'Impact', 
                                                        'Verdana',
                                                        'Georgia',
                                                        'Comic Sans MS'
                                                      ].map((f) => DropdownMenuItem(value: f, child: Text(f, style: TextStyle(fontFamily: f)))).toList(),
                                                      onChanged: (v) {
                                                         if (v == null) return;
                                                         final newParams = Map<String, dynamic>.from(activeLayer.effectParams);
                                                         newParams[key] = v;
                                                         context.read<ShowState>().updateLayer(
                                                            target: _selectedLayer, 
                                                            params: newParams
                                                         );
                                                      },
                                                    ),
                                                  ),
                                                )

                                             // 3. Text Input
                                             ] else if (value is String) ...[
                                                 TextFormField(
                                                    initialValue: value,
                                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                                    decoration: InputDecoration(
                                                       isDense: true,
                                                       filled: true,
                                                       fillColor: Colors.white10,
                                                       border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                                    ),
                                                    onChanged: (v) {
                                                       final newParams = Map<String, dynamic>.from(activeLayer.effectParams);
                                                       newParams[key] = v;
                                                       context.read<ShowState>().updateLayer(
                                                          target: _selectedLayer, 
                                                          params: newParams
                                                       );
                                                    },
                                                 )

                                             // 3.5 ENUM SELECTOR (Radio/Chips)
                                             ] else if (value is num && EffectService.effects.firstWhere((e) => e.type == activeLayer.effect).enumOptions?.containsKey(key) == true) ...[
                                                 Builder(builder: (c) {
                                                    final def = EffectService.effects.firstWhere((e) => e.type == activeLayer.effect);
                                                    final options = def.enumOptions![key]!;
                                                    final currentIdx = value.toInt();
                                                    
                                                    return Padding(
                                                      padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
                                                      child: Wrap(
                                                         spacing: 4, runSpacing: 4,
                                                         children: List.generate(options.length, (i) {
                                                            final isSelected = i == currentIdx;
                                                            return InkWell(
                                                               onTap: () {
                                                                   final newParams = Map<String, dynamic>.from(activeLayer.effectParams);
                                                                   newParams[key] = i.toDouble();
                                                                   context.read<ShowState>().updateLayer(target: _selectedLayer, params: newParams);
                                                               },
                                                               child: AnimatedContainer(
                                                                  duration: const Duration(milliseconds: 150),
                                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                                  decoration: BoxDecoration(
                                                                     color: isSelected ? const Color(0xFF2196F3) : Colors.white.withOpacity(0.05),
                                                                     borderRadius: BorderRadius.circular(6),
                                                                     border: Border.all(color: isSelected ? Colors.blueAccent : Colors.transparent),
                                                                  ),
                                                                  child: Text(options[i].toUpperCase(), style: TextStyle(
                                                                     color: isSelected ? Colors.white : Colors.white54,
                                                                     fontSize: 10, fontWeight: FontWeight.bold
                                                                  )),
                                                               ),
                                                            );
                                                         }),
                                                      ),
                                                    );
                                                 }),

                                             // 3.5 COUNT STEPPER
                                             ] else if (key == 'count' && value is num) ...[
                                                 Builder(builder: (context) {
                                                    final def = EffectService.effects.firstWhere((e) => e.type == activeLayer.effect);
                                                    double min = def.minParams[key]?.toDouble() ?? 1.0;
                                                    double max = def.maxParams[key]?.toDouble() ?? 100.0;
                                                    int current = value.toInt();
                                                    
                                                    return Row(
                                                      children: [
                                                         Container(
                                                            decoration: BoxDecoration(
                                                               color: Colors.white10,
                                                               borderRadius: BorderRadius.circular(20),
                                                            ),
                                                            child: IconButton(
                                                               icon: const Icon(Icons.remove, size: 16, color: Colors.white),
                                                               constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                                                               onPressed: () {
                                                                  double newVal = (current - 1).toDouble();
                                                                  if (newVal < min) newVal = min;
                                                                  final newParams = Map<String, dynamic>.from(activeLayer.effectParams);
                                                                  newParams[key] = newVal;
                                                                  context.read<ShowState>().updateLayer(target: _selectedLayer, params: newParams);
                                                               },
                                                            )
                                                         ),
                                                         Padding(
                                                            padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                                            child: Text("$current", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                         ),
                                                         Container(
                                                            decoration: BoxDecoration(
                                                               color: Colors.white10,
                                                               borderRadius: BorderRadius.circular(20),
                                                            ),
                                                            child: IconButton(
                                                               icon: const Icon(Icons.add, size: 16, color: Colors.white),
                                                               constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                                                               onPressed: () {
                                                                  double newVal = (current + 1).toDouble();
                                                                  if (newVal > max) newVal = max;
                                                                  final newParams = Map<String, dynamic>.from(activeLayer.effectParams);
                                                                  newParams[key] = newVal;
                                                                  context.read<ShowState>().updateLayer(target: _selectedLayer, params: newParams);
                                                               },
                                                            )
                                                         ),
                                                      ],
                                                    );
                                                 }),

                                             // 4. Slider (Double) (Fallback)
                                             ] else if (value is num) ...[
                                                 Builder(builder: (context) {
                                                    final def = EffectService.effects.firstWhere((e) => e.type == activeLayer.effect);
                                                    double min = def.minParams[key]?.toDouble() ?? 0.0;
                                                    double max = def.maxParams[key]?.toDouble() ?? 1.0;
                                                    double dVal = value.toDouble();
                                                    
                                                    return Row(
                                                      children: [
                                                         Expanded(
                                                           child: SliderTheme(
                                                             data: SliderTheme.of(context).copyWith(
                                                               trackHeight: 2,
                                                               thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                                               overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                                             ),
                                                             child: Slider(
                                                               value: dVal.clamp(min, max),
                                                               min: min,
                                                               max: max,
                                                               activeColor: const Color(0xFF90CAF9),
                                                               inactiveColor: Colors.white12,
                                                               onChanged: (v) {
                                                                  final newParams = Map<String, dynamic>.from(activeLayer.effectParams);
                                                                  newParams[key] = v;
                                                                  context.read<ShowState>().updateLayer(
                                                                     target: _selectedLayer, 
                                                                     params: newParams
                                                                  );
                                                               },
                                                             ),
                                                           ),
                                                         ),
                                                         SizedBox(width: 24, child: Text(dVal.toStringAsFixed(1), style: const TextStyle(color: Colors.white54, fontSize: 10), textAlign: TextAlign.right)),
                                                      ],
                                                    );
                                                 })
                                             ]
                                           ],
                                         ),
                                       );
                                  }),
                                ],
                              ),
                        ],
                  
                  // ALWAYS SHOW EFFECTS LIBRARY
                  const SizedBox(height: 24),
                  if (activeLayer.type != LayerType.none) ...[
                     const Divider(color: Colors.white10, height: 1),
                     const SizedBox(height: 24),
                  ],

                    Text("EFFECTS LIBRARY", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),

                     Wrap(
                       key: const ValueKey("EffectsLibraryWrap"),
                       spacing: 8,
                       runSpacing: 8,
                       children: EffectService.effects.map((e) {
                           final bool isEnabled = show.fixtures.isNotEmpty;
                           return SizedBox(
                              width: 52, // Approx 320 / 5 - spacing
                              height: 52,
                              child: InkWell(
                                  onTap: isEnabled ? () {
                                    if (activeLayer.type != LayerType.none && activeLayer.effect != e.type) { 
                                       // Show Confirmation Dialog
                                       showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                             title: const Text("Replace Content?"),
                                             content: Text("Replace current content with ${e.name}?"),
                                             backgroundColor: const Color(0xFF222222),
                                             actions: [
                                                TextButton(
                                                   onPressed: () => Navigator.pop(ctx),
                                                   child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
                                                ),
                                                TextButton(
                                                   onPressed: () {
                                                      Navigator.pop(ctx); // Close Dialog
                                                      _applyEffect(e);
                                                   },
                                                   child: const Text("Replace", style: TextStyle(color: Colors.greenAccent)),
                                                ),
                                             ],
                                          )
                                       );
                                    } else {
                                       _applyEffect(e);
                                    }
                                  } : null,
                                  child: Tooltip(
                                    message: e.name, 
                                    child: Opacity(
                                       opacity: isEnabled ? 1.0 : 0.3,
                                       child: Container(
                                          decoration: BoxDecoration(
                                             color: Colors.black,
                                             borderRadius: BorderRadius.circular(4),
                                             border: activeLayer.type == LayerType.effect && activeLayer.effect == e.type 
                                                 ? Border.all(color: Colors.blueAccent, width: 2)
                                                 : Border.all(color: Colors.white12),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: Stack(
                                             fit: StackFit.expand,
                                             children: [
                                                EffectRenderer(
                                                  type: e.type,
                                                  params: e.defaultParams,
                                                  isPlaying: false, 
                                                  initialTime: 5.0,
                                                ),
                                             ],
                                          ),
                                       ),
                                    ),
                                  ),
                               ),
                           );
                       }).toList(),
                     ),
                    ],
                  ),
                ),
              ), 

              // Main Content Area (Video Tab)
              Expanded(
                 child: Container(
                   color: const Color(0xFF1E1E1E), // "Void" Color
                   child: ClipRect(
                     child: LayoutBuilder(
                       builder: (context, constraints) {
                          _lastViewportSize = constraints.biggest;

                          // 1. Calculate Matrix Bounds (Logical 10.0 scale)
                          final show = context.read<ShowState>().currentShow;
                          if (show == null) return const SizedBox();


                          bool hasFixtures = show.fixtures.isNotEmpty;
                          
                          
                          double minX = 0;
                          double minY = 0;
                          double matW = 1000;
                          double matH = 1000;
                          
                          if (hasFixtures) {
                              final bounds = _calculateMatrixBounds(show);
                              minX = bounds.left;
                              minY = bounds.top;
                              matW = bounds.width;
                              matH = bounds.height;
                          }
                          
                          if (matW <= 0) matW = 1000;
                          if (matH <= 0) matH = 1000;
                          
                          return Focus(
                            autofocus: true,
                            onKey: (node, event) {
                               if (event is RawKeyDownEvent) { // KeyDown Only
                                  if (event.logicalKey == LogicalKeyboardKey.delete) {
                                     _deleteSelectedObject();
                                     return KeyEventResult.handled;
                                  } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                                     _deselectAll();
                                     return KeyEventResult.handled;
                                  }
                               }
                               return KeyEventResult.ignored;
                            },
                            child: Listener(
                             onPointerSignal: _onMouseWheel,
                             child: InteractiveViewer(
                               transformationController: _zoomController,
                               boundaryMargin: const EdgeInsets.all(double.infinity),
                               minScale: 0.01,
                               maxScale: 20.0,
                               constrained: false, // Infinite Canvas
                               child: Center(
                                 child: RepaintBoundary(
                                   key: _previewKey,
                                   child: GestureDetector(
                                     behavior: HitTestBehavior.translucent, // Catch all clicks
                                     onTapUp: _handleCanvasTap,
                                     onSecondaryTapUp: _handleCanvasRightClick,
                                     child: Container(
                                       // Explicitly size the "Canvas" to match Setup Tab (3200x1600)
                                       width: 3200,
                                       height: 1600,
                                       decoration: const BoxDecoration(
                                         color: Color(0xFF121212), // "Canvas" Color
                                         boxShadow: [BoxShadow(color: Colors.black, blurRadius: 40, spreadRadius: 10)],
                                       ),
                                       child: MouseRegion(
                                      onEnter: (_) {
                                         if (!_isHoveringWorkspace) setState(() => _isHoveringWorkspace = true);
                                      },
                                      onExit: (_) {
                                         if (_isHoveringWorkspace) setState(() => _isHoveringWorkspace = false);
                                      },
                                      child: Stack(
                                        alignment: Alignment.center,
                                        clipBehavior: Clip.none,
                                        children: [
                                           // 0. Grid Background (Matches Setup Tab)
                                           Positioned.fill(
                                              child: CustomPaint(
                                                 painter: GridBackgroundPainter(),
                                              ),
                                           ),
 
                                           // 0.5. Fixture Overlay (Behind Layers)
                                           if (hasFixtures)
                                              Positioned.fill(
                                                 child: IgnorePointer(
                                                    child: CustomPaint(
                                                       painter: FixtureOverlayPainter(show.fixtures),
                                                    ),
                                                 ),
                                              ), 
 
                                           // 1. Video Layers
                                           ..._buildLayerStack(show, matW, matH),
                                           
                                           // 2. Selection / Gizmos (Already handled inside _buildLayerStack with correct Z-order)
                                           // REMOVED individual selection overlay to fix Z-Order issues.
 
                                           // 3. Effect Overlay - REMOVED (Caused scaling issues)
                                              
                                            // 4. Crop Overlay (If Cropping)
                                            if (activeLayer.transform?.crop != null)
                                               const SizedBox(), 
                                        ],
                                      ), // Stack Inner (1936)
                                    ), // MouseRegion (1929)
                                  ), // Container (1921)
                                ), // GestureDetector (1917)
                              ), // RepaintBoundary (1916)
                            ), // Center (1914)
                          ), // InteractiveViewer (1908)
                        ), // Listener (1906)
                      ); // Focus (1892)
                   }, // Builder
                 ), // LayoutBuilder
              ), // ClipRect
           ), // Container
        ), // Expanded
       ], // Row children
     ), // Row
   ], // Stack Outer children
 ); // Stack Outer
      },
    );
  }
  
  void _syncPixelEngine(ShowManifest show) {
     final engine = context.read<PixelEngine>();
     
     // Set Render Source if not already
     if (engine.repaintBoundaryKey != _previewKey) {
        engine.setBoundary(_previewKey);
     }
     
     // Set Manifest
     engine.setManifest(show);
     
     // Start/Stop
     // Only run if Global Playback AND Pixel Mapping Switch are both ON
     if (context.read<ShowState>().isPlaying && context.read<ShowState>().isPixelMappingEnabled) {
        engine.start();
     } else {
        engine.stop();
     }
  }
  void _calculateIntersection() {
    final show = context.read<ShowState>().currentShow;
    if (show == null) return;
    
    LayerConfig activeLayer = switch(_selectedLayer) {
       LayerTarget.background => show.backgroundLayer,
       LayerTarget.middle => show.middleLayer,
       LayerTarget.foreground => show.foregroundLayer,
    };
    final transform = activeLayer.transform ?? const MediaTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0);

    final size = _resolveLayerSize(show, activeLayer);
    final width = size.width;
    final height = size.height;
    
    if (show.fixtures.isEmpty || width <= 0 || height <= 0) {
       if (_currentIntersection != null) {
         if (mounted)
         setState(() {
            _currentIntersection = null;
            _intersectW = 0;
            _intersectH = 0;
            _displayX = 0;
            _displayY = 0;
         });
       }
       return;
    }

    // 1. Matrix Bounds (Logic Space)
    final bounds = _calculateMatrixBounds(show);
    if (bounds.width <= 0 || bounds.height <= 0) {
        if (_currentIntersection != null) {
           if (mounted)
           setState(() {
              _currentIntersection = null;
              _intersectW = 0;
              _intersectH = 0;
              _displayX = 0;
              _displayY = 0;
           });
        }
        return;
    }

    double matW = bounds.width;
    double matH = bounds.height;
    
    // Matrix Rect relative to Center (0,0)
    Rect matrixRect = Rect.fromCenter(center: Offset.zero, width: matW, height: matH);

    // 2. Video Bounds (Logic Space) relative to Matrix Center
    
    final vidW = width.toDouble();
    final vidH = height.toDouble();
    
    // Scaled Size
    final scaledW = vidW * transform.scaleX;
    final scaledH = vidH * transform.scaleY;
    
    // TopLeft of Video relative to Center (0,0)
    // Center is at t.translateX, t.translateY
    final vidLeft = transform.translateX - (scaledW / 2);
    final vidTop = transform.translateY - (scaledH / 2);
    
    Rect videoRect = Rect.fromLTWH(vidLeft, vidTop, scaledW, scaledH);
    
    // 3. Intersect
    Rect intersect = matrixRect.intersect(videoRect);
    
       if (intersect.width > 0 && intersect.height > 0) {
       // Calculate Grid Resolution
       int w = (intersect.width / kGridSize).round();
       int h = (intersect.height / kGridSize).round();
       
       // Calculate Display Coordinates (Bottom-Left Origin)
       // X Start: Distance from Left Edge
       double matLeft = matrixRect.left;
       double xDist = intersect.left - matLeft;
       int dX = (xDist / kGridSize).round();

       // Y Start: Distance from Bottom Edge (Flutter Y grows down)
       // Matrix Bottom (Max Y) - Intersect Bottom (Max Y of intersection)
       double matBottom = matrixRect.bottom;
       double yDist = matBottom - intersect.bottom; 
       int dY = (yDist / kGridSize).round();

       if (mounted)
       setState(() {
          _currentIntersection = intersect;
          _intersectW = w;
          _intersectH = h;
          _displayX = dX;
          _displayY = dY;
       });
    } else {
       if (_currentIntersection != null) {
          if (mounted)
          setState(() {
            _currentIntersection = null;
             _intersectW = 0;
             _intersectH = 0;
             _displayX = 0;
             _displayY = 0;
            });
        }
    }
  }
   
   void _fitViewToMatrix() {
      final show = context.read<ShowState>().currentShow;
      if (show == null || show.fixtures.isEmpty) return;
      
      final bounds = _calculateMatrixBounds(show);
      if (bounds.isEmpty) return;
      
      // Target Viewport Size (with padding)
      final double pad = 40.0;
      final double targetW = (_lastViewportSize?.width ?? 1000.0) - pad * 2;
      final double targetH = (_lastViewportSize?.height ?? 800.0) - pad * 2;
      
      double sX = targetW / bounds.width;
      double sY = targetH / bounds.height;
      double scale = min(sX, sY).clamp(0.1, 5.0); // Clamp reasonable zoom
      
      // Center of Matrix
      final mx = bounds.center.dx;
      final my = bounds.center.dy;
      
      // Standard InteractiveViewer reset:
      // We want to center (mx, my) at the viewport center.
      final double vpCX = (_lastViewportSize?.width ?? 1000.0) / 2.0;
      final double vpCY = (_lastViewportSize?.height ?? 800.0) / 2.0;
      
      // Logic: Translate matrix center to (0,0), scale, then move to viewport center.
      _zoomController.value = Matrix4.identity()
          ..translate(-mx * scale + vpCX, -my * scale + vpCY) 
          ..scale(scale);
          
      debugPrint("Fit View: Scale $scale, Center $mx,$my");
   }
   
   void _applyEffect(EffectDef e) {
      // 1. Calculate Scale & Position to Fit Matrix
      final show = context.read<ShowState>().currentShow;
      double scaleX = 1.0;
      double scaleY = 1.0;
      double tx = 0.0;
      double ty = 0.0;
      
      if (show != null && show.fixtures.isNotEmpty) {
          final bounds = _calculateMatrixBounds(show);
          
          if (bounds.width > 0 && bounds.height > 0) {
             // Default Effect Size is 1920x1080
             // Add bleed (2px) for perfect edge
             final w = bounds.width + 2.0;
             final h = bounds.height + 2.0;
             
             scaleX = w / 1920.0;
             scaleY = h / 1080.0;
             
             // Position relative to Canvas Center (1600, 800)
             final boundsCenterX = bounds.center.dx;
             final boundsCenterY = bounds.center.dy;
             
             tx = boundsCenterX - 1600.0;
             ty = boundsCenterY - 800.0;
          }
      }
          

      context.read<ShowState>().updateLayer(
         target: _selectedLayer,
         type: LayerType.effect,
         effect: e.type,
         opacity: 1.0, 
         params: e.defaultParams,
         lockAspectRatio: false, // Allow Stretch for Effects
         transform: MediaTransform(
            scaleX: scaleX, 
            scaleY: scaleY, 
            translateX: tx, 
            translateY: ty, 
            rotation: 0
         )
      );
      setState(() {
        context.read<ShowState>().setPlaying(true);
      });
      
      // Trigger intersection update
      WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _calculateIntersection();
      });
   }

  // MARK: - State
  // ... existing state ...
  bool _hasActiveSelection = false; // Tracks if an object is explicitly selected

  // MARK: - Selection & Hit Testing

  void _deselectAll() {
     setState(() {
        _hasActiveSelection = false;
        // We keep _selectedLayer as is, or reset to BG?
        // User said "all objects will be deselected".
        // Param pane relies on _selectedLayer. We will hide it if _hasActiveSelection is false.
     });
  }

  void _deleteSelectedObject() {
     if (!_hasActiveSelection) return;
     context.read<ShowState>().updateLayer(
        target: _selectedLayer,
        type: LayerType.none,
     );
     _deselectAll();
     _calculateIntersection();
  }

  String _getFriendlyLayerName(LayerConfig layer) {
      String contentName = "Empty";
      if (layer.type == LayerType.video) {
         contentName = p.basename(layer.path ?? "");
         contentName += "(video)";
      } else if (layer.type == LayerType.effect) {
         contentName = layer.effect?.name.split('.').last ?? "Unknown";
         if (contentName.isNotEmpty) {
            contentName = contentName[0].toUpperCase() + contentName.substring(1);
         }
         contentName += "(effect)";
      }
      return contentName;
  }

  void _handleCanvasTap(TapUpDetails details) {
      // Local Position relative to the 3200x1600 Canvas Container
      final hits = _hitTest(details.localPosition);
      
      if (hits.isEmpty) {
         setState(() {
            _hasActiveSelection = false;
         });
      } else if (hits.length == 1) {
         setState(() {
            _selectedLayer = hits.first;
            _hasActiveSelection = true;
         });
      } else {
         // Show Selection Menu
          final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
          final RelativeRect position = RelativeRect.fromRect(
             Rect.fromPoints(details.globalPosition, details.globalPosition),
             Offset.zero & overlay.size,
          );
          
          // Context Menu Theme
          final menuShape = RoundedRectangleBorder(
             side: BorderSide(color: Colors.grey[800]!),
             borderRadius: BorderRadius.circular(8),
          );
          final menuColor = const Color(0xFF252525);
          final textStyle = const TextStyle(color: Colors.white, fontSize: 13);

          showMenu(
             context: context,
             position: position,
             shape: menuShape,
             color: menuColor,
             items: <PopupMenuEntry<LayerTarget>>[
                PopupMenuItem<LayerTarget>(
                   enabled: false,
                   child: Row(
                      children: [
                         Icon(Icons.touch_app, color: Colors.white70, size: 16),
                         const SizedBox(width: 8),
                         Text("Object to select", style: textStyle.copyWith(color: Colors.white70, fontStyle: FontStyle.italic)),
                      ],
                   ),
                ),
                const PopupMenuDivider(),
                ...hits.map((target) {
                final show = context.read<ShowState>().currentShow;
                String displayName = target.name;
                if (show != null) {
                    final layer = switch(target) {
                       LayerTarget.background => show.backgroundLayer,
                       LayerTarget.middle => show.middleLayer,
                       LayerTarget.foreground => show.foregroundLayer,
                    };
                    String name = _getFriendlyLayerName(layer);
                    String layerName = target.name;
                    if (layerName.isNotEmpty) {
                       layerName = layerName[0].toUpperCase() + layerName.substring(1);
                    }
                    displayName = "$name ($layerName)";
                }
             
                return PopupMenuItem<LayerTarget>(
                   value: target,
                   onTap: () {
                     setState(() {
                        _selectedLayer = target;
                        _hasActiveSelection = true;
                     });
                   },
                   child: Text(displayName, style: textStyle),
                );
             }).toList()],
          );
      }
  }

  void _handleCanvasRightClick(TapUpDetails details) {
      final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
      final RelativeRect position = RelativeRect.fromRect(
         Rect.fromPoints(details.globalPosition, details.globalPosition),
         Offset.zero & overlay.size,
      );

      // Context Menu Theme
      final menuShape = RoundedRectangleBorder(
         side: BorderSide(color: Colors.grey[800]!),
         borderRadius: BorderRadius.circular(8),
      );
      final menuColor = const Color(0xFF252525);
      final textStyle = const TextStyle(color: Colors.white, fontSize: 13);
      final iconColor = Colors.white70;
      final double iconSize = 16;

      if (!_hasActiveSelection) {
         showMenu(
            context: context,
            position: position,
            shape: menuShape,
            color: menuColor,
            items: [
               PopupMenuItem(
                  enabled: false,
                  child: Text("Please select an object first", style: textStyle.copyWith(color: Colors.white54)),
               )
            ]
         );
         return;
      }
      
      // Use currently selected layer
      final targetToSelect = _selectedLayer;

      // Get Friendly Name for Header
      String headerName = "Selected Object";
      final show = context.read<ShowState>().currentShow;
      if (show != null) {
          final layer = switch(targetToSelect) {
             LayerTarget.background => show.backgroundLayer,
             LayerTarget.middle => show.middleLayer,
             LayerTarget.foreground => show.foregroundLayer,
          };
          
          String contentName = _getFriendlyLayerName(layer);
          
          String layerName = targetToSelect.name;
          if (layerName.isNotEmpty) {
             layerName = layerName[0].toUpperCase() + layerName.substring(1);
          }
          headerName = "$contentName ($layerName)";
      }
          


      showMenu(
         context: context,
         position: position,
         shape: menuShape,
         color: menuColor,
         items: <PopupMenuEntry<dynamic>>[
            PopupMenuItem(
               enabled: false, // Header is label
               child: Row(
                  children: [
                     Icon(Icons.info_outline, color: iconColor, size: iconSize),
                     const SizedBox(width: 8),
                     Text(headerName, style: textStyle.copyWith(color: Colors.white70, fontStyle: FontStyle.italic)),
                  ],
               ),
            ),
            const PopupMenuDivider(),
            // Direct Move Options (Flattened)
            if (targetToSelect != LayerTarget.background)
            PopupMenuItem(
               value: 'move_bg',
               onTap: () => _moveLayer(targetToSelect, LayerTarget.background),
               child: Row(
                 children: [
                    Icon(Icons.layers, color: iconColor, size: iconSize),
                    const SizedBox(width: 8),
                    Text("Move to Background", style: textStyle),
                 ],
               ),
            ),
            if (targetToSelect != LayerTarget.middle)
            PopupMenuItem(
               value: 'move_md',
               onTap: () => _moveLayer(targetToSelect, LayerTarget.middle),
               child: Row(
                 children: [
                    Icon(Icons.layers, color: iconColor, size: iconSize),
                    const SizedBox(width: 8),
                    Text("Move to Middle", style: textStyle),
                 ],
               ),
            ),
            if (targetToSelect != LayerTarget.foreground)
            PopupMenuItem(
               value: 'move_fg',
               onTap: () => _moveLayer(targetToSelect, LayerTarget.foreground),
               child: Row(
                 children: [
                    Icon(Icons.layers, color: iconColor, size: iconSize),
                    const SizedBox(width: 8),
                    Text("Move to Foreground", style: textStyle),
                 ],
               ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
               value: 'delete',
               onTap: _deleteSelectedObject,
               child: Row(
                  children: [
                     Icon(Icons.delete, color: Colors.redAccent, size: iconSize),
                     const SizedBox(width: 8),
                     Text("Delete Object", style: textStyle.copyWith(color: Colors.redAccent)),
                  ],
               ),
            ),
         ],
      );
  }
  
  void _moveLayer(LayerTarget source, LayerTarget dest) {
      final show = context.read<ShowState>().currentShow;
      if (show == null) return;
      
      final sourceLayer = switch(source) {
         LayerTarget.background => show.backgroundLayer,
         LayerTarget.middle => show.middleLayer,
         LayerTarget.foreground => show.foregroundLayer,
      };
      
      final destLayer = switch(dest) {
         LayerTarget.background => show.backgroundLayer,
         LayerTarget.middle => show.middleLayer,
         LayerTarget.foreground => show.foregroundLayer,
      };
      
      // If destination is occupied
      if (destLayer.type != LayerType.none) {
         String destObjectName = _getFriendlyLayerName(destLayer);
         showDialog(
            context: context,
            builder: (c) => AlertDialog(
               title: const Text("Destination layer conflict"),
               content: Text("The ${dest.name} layer already contains '$destObjectName'."),
               actions: [
                  TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
                  TextButton(
                     onPressed: () {
                        Navigator.pop(c);
                        _performMove(source, dest, sourceLayer, destLayer, swap: false);
                     }, 
                     child: const Text("Replace", style: TextStyle(color: Colors.orange))
                  ),
                  TextButton(
                     onPressed: () {
                        Navigator.pop(c);
                        _performMove(source, dest, sourceLayer, destLayer, swap: true);
                     },
                     child: const Text("Swap", style: TextStyle(color: Colors.blue))
                  ),
               ],
            )
         );
      } else {
         _performMove(source, dest, sourceLayer, destLayer, swap: false);
      }
  }

  void _performMove(LayerTarget source, LayerTarget dest, LayerConfig srcConfig, LayerConfig destConfig, {required bool swap}) {
      final state = context.read<ShowState>();
      
      // Move Source -> Dest
      state.updateLayer(
         target: dest,
         type: srcConfig.type,
         path: srcConfig.path,
         effect: srcConfig.effect,
         params: srcConfig.effectParams,
         opacity: srcConfig.opacity,
         isVisible: srcConfig.isVisible,
         transform: srcConfig.transform,
         lockAspectRatio: srcConfig.lockAspectRatio,
      );
      
      if (swap) {
         // Move Dest -> Source
         state.updateLayer(
            target: source,
            type: destConfig.type,
            path: destConfig.path,
            effect: destConfig.effect,
            params: destConfig.effectParams,
            opacity: destConfig.opacity,
            isVisible: destConfig.isVisible,
            transform: destConfig.transform,
            lockAspectRatio: destConfig.lockAspectRatio,
         );
      } else {
         // Clear Source
         state.updateLayer(
            target: source,
            type: LayerType.none,
         );
      }
      
      // Update Selection to follow the moved object (Dest)
      setState(() {
         _selectedLayer = dest;
         _hasActiveSelection = true;
      });
      _calculateIntersection();
  }

  List<LayerTarget> _hitTest(Offset localPos) {
      List<LayerTarget> hits = [];
      // Canvas Spec: 3200x1600. Center: 1600, 800.
      final center = const Offset(1600, 800);
      
      // Iterate Reverse Z-Order (FG -> MD -> BG)
      final show = context.read<ShowState>().currentShow;
      if (show == null) return [];

      final targets = [LayerTarget.foreground, LayerTarget.middle, LayerTarget.background];
      
      for (var target in targets) {
         final layer = switch(target) {
            LayerTarget.foreground => show.foregroundLayer,
            LayerTarget.middle => show.middleLayer,
            LayerTarget.background => show.backgroundLayer,
         };
         
         if (layer.type == LayerType.none || !layer.isVisible) continue;
         
         final size = _resolveLayerSize(show, layer); // w, h
         if (size.width <= 0 || size.height <= 0) continue;

         // Transform Point to Layer Local Space
         final t = layer.transform ?? const MediaTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0);
         
         final matrix = Matrix4.identity()
           ..translate(center.dx + t.translateX, center.dy + t.translateY)
           ..rotateZ(t.rotation * 3.14159 / 180)
           ..scale(t.scaleX == 0 ? 0.001 : t.scaleX, t.scaleY == 0 ? 0.001 : t.scaleY);
           
         final inverse = Matrix4.tryInvert(matrix);
         if (inverse == null) continue;
         
         final localPoint3 = inverse.transform3(Vector3(localPos.dx, localPos.dy, 0));
         final lx = localPoint3.x;
         final ly = localPoint3.y;
         
         // In local space, object is centered at 0,0 with size w,h
         // Bounds: -w/2 to w/2
         if (lx >= -size.width/2 && lx <= size.width/2 &&
             ly >= -size.height/2 && ly <= size.height/2) {
             hits.add(target);
         }
      }
      
      return hits;
  }

  // MARK: - Layer Rendering
  
   List<Widget> _buildLayerStack(ShowManifest show, double matW, double matH) {
     return [
        _buildStackedLayer(LayerTarget.background, show.backgroundLayer, matW, matH),
        _buildStackedLayer(LayerTarget.middle, show.middleLayer, matW, matH),
        _buildStackedLayer(LayerTarget.foreground, show.foregroundLayer, matW, matH),
     ];
  }

  Widget _buildStackedLayer(LayerTarget target, LayerConfig layer, double matW, double matH) {
      if (layer.type == LayerType.none || !layer.isVisible) return const SizedBox();
      
      // Selection Logic: MATCHED layer AND Explicit Selection Active
      bool isSelected = _selectedLayer == target && _hasActiveSelection;
      
      if (isSelected) {
         return _buildInteractableLayer(target, layer, matW, matH);
      } else {
         return IgnorePointer(
            child: _buildLayer(layer, matW, matH)
         );
      }
  }

  Widget _buildInteractableLayer(LayerTarget target, LayerConfig layer, double matW, double matH) {
      final show = context.read<ShowState>().currentShow;
      if (show == null) return const SizedBox();
      final size = _resolveLayerSize(show, layer);
      
      // Calculate Bounds for Constraint
      final bounds = _calculateMatrixBounds(show);

      return TransformGizmo(
        key: ValueKey("gizmo_$target"),
        transform: layer.transform ?? const MediaTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0),
        isSelected: true,
        contentSize: size, 
        lockAspect: layer.type == LayerType.video ? layer.lockAspectRatio : false,
        onUpdate: (newT) {
           final constrained = _constrainTransform(newT, layer, bounds);
           context.read<ShowState>().updateLayer(
              target: target,
              transform: constrained
           );
           _calculateIntersection();
        },
        onDoubleTap: () {
           // Auto-Fit Logic
           if (bounds.width > 0 && bounds.height > 0) {
               double sX = (bounds.width + 2.0) / size.width;
               double sY = (bounds.height + 2.0) / size.height;
               double tx = bounds.center.dx - 1600.0;
               double ty = bounds.center.dy - 800.0;
               
               context.read<ShowState>().updateLayer(
                  target: target,
                  transform: MediaTransform(scaleX: sX, scaleY: sY, translateX: tx, translateY: ty, rotation: 0)
               );
               _calculateIntersection();
           }
        },
        onInteractionStart: () => setState(() => _isInteracting = true),
        onInteractionEnd: () => setState(() => _isInteracting = false),
        child: _buildLayerContent(layer, size.width, size.height),
      );
  }


  Widget _buildLayer(LayerConfig layer, double matW, double matH) {
       if (layer.type == LayerType.none) return const SizedBox();
       
       final show = context.read<ShowState>().currentShow;
       if (show == null) return const SizedBox();
       final size = _resolveLayerSize(show, layer);
       
       final t = layer.transform ?? const MediaTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0);
       
       return Center(
         child: Transform(
           transform: Matrix4.identity()
             ..translate(t.translateX, t.translateY)
             ..scale(
                t.scaleX == 0 ? 0.001 : t.scaleX, 
                t.scaleY == 0 ? 0.001 : t.scaleY
             )
             ..rotateZ(t.rotation * 3.14159 / 180),
           alignment: Alignment.center,
           child: _buildLayerContent(layer, size.width, size.height)
         ),
       );
  }
  
  // Base Content Builder (Natural Size)
  Widget _buildLayerContent(LayerConfig layer, double width, double height) {
       if (layer.type == LayerType.video) {
           final show = context.read<ShowState>().currentShow;
           Player? p;
           if (layer == show?.backgroundLayer) p = _bgPlayer;
           else if (layer == show?.middleLayer) p = _mdPlayer;
           else if (layer == show?.foregroundLayer) p = _fgPlayer;
           
           if (p == null) return const SizedBox();
           
           // We use the player directly
            return Opacity(
              opacity: layer.opacity,
              child: SizedBox(
                width: width,
                height: height,
                child: Video(controller: VideoController(p), fit: BoxFit.fill, controls: NoVideoControls)
              ),
            );
       } else {
             return Opacity(
               opacity: layer.opacity,
               child: SizedBox(
                 width: width,
                 height: height,
                 child: EffectRenderer(type: layer.effect, params: layer.effectParams, isPlaying: context.read<ShowState>().isPlaying)
               ),
             );
       }
  }

  // MARK: - UI Helpers

  Widget _buildInfoRow(String label, String value, {bool isHighlight = false}) {
     return Row(
       mainAxisAlignment: MainAxisAlignment.spaceBetween,
       children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          Text(value, style: TextStyle(
             color: isHighlight ? const Color(0xFF90CAF9) : Colors.white, 
             fontSize: 11, 
             fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal
          )),
       ],
     );
  }

  void _loadEffectDefaults(EffectType type) {
     try {
       final def = EffectService.effects.firstWhere((e) => e.type == type);
       // Update ShowState directly
       context.read<ShowState>().updateLayer(
          target: _selectedLayer, 
          params: def.defaultParams
       );
       setState(() {
          context.read<ShowState>().setPlaying(true);
       });
     } catch (e) {
       debugPrint("Error loading defaults for $type: $e");
     }
  }

  Widget _buildModernButton({required IconData icon, required String label, required Color color, required VoidCallback? onTap, bool isEnabled = true}) {
      return FilledButton(
        onPressed: isEnabled ? onTap : null,
        style: FilledButton.styleFrom(
          backgroundColor: isEnabled ? color.withValues(alpha: 0.8) : Colors.white10,
          foregroundColor: isEnabled ? Colors.white : Colors.white38,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: EdgeInsets.zero,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ],
        ),
      );
  }

    // Constraint helper
    // Constraint helper
  MediaTransform _constrainTransform(MediaTransform t, LayerConfig layer, Rect bounds) {      
     final layerSize = _resolveLayerSize(context.read<ShowState>().currentShow!, layer);
     if (bounds.isEmpty) return t;

     // 1. Clamp Scale (Max Size = Matrix Size)
     double scaleX = t.scaleX;
     double scaleY = t.scaleY;
     
     final maxSX = bounds.width / layerSize.width;
     final maxSY = bounds.height / layerSize.height;
     
     bool isLocked = layer.type == LayerType.video ? layer.lockAspectRatio : false;

     if (isLocked) {
         double factor = 1.0;
         if (scaleX > maxSX) factor = maxSX / scaleX;
         if (scaleY * factor > maxSY) factor = (maxSY / scaleY) * factor; 
         
         if (factor < 1.0) {
             scaleX *= factor;
             scaleY *= factor;
         }
     } else {
         if (scaleX > maxSX) scaleX = maxSX;
         if (scaleY > maxSY) scaleY = maxSY;
     }

     // 2. Clamp Translation (Stay within Bounds)
     // VideoRect MUST be contained within MatrixRect (or touch edges)
     // Actually, users usually want "Center shouldn't leave the Matrix"? 
     // Or "Edges shouldn't leave Matrix"?
     // User said: "corners outside perimeter... not allowed".
     // This means Containment: VideoRect <= MatrixRect.
     
     // Calculate Video Dimensions
     final vidW = layerSize.width * scaleX;
     final vidH = layerSize.height * scaleY;
     
     // Matrix Bounds relative to Canvas Center (1600, 800)
     // _calculateMatrixBounds returns absolute positions.
     // Canvas Center is (1600, 800).
     // Matrix Rect in Canvas Space = Rect.fromLTWH(bounds.left - 1600, bounds.top - 800, bounds.width, bounds.height).
     // Wait. t.translateX/Y are relative to (0,0) center of stack.
     // Stack is 3200x1600.
     // (0,0) matches Canvas (1600, 800).
     // So Matrix Rect relative to Center:
     final matLeft = bounds.left - 1600.0;
     final matTop = bounds.top - 800.0;
     final matRight = bounds.right - 1600.0;
     final matBottom = bounds.bottom - 800.0;
     
     double tx = t.translateX;
     double ty = t.translateY;
     
     // Video Rect relative to Center
     // Left = tx - vidW/2. Right = tx + vidW/2.
     // Constraint: Left >= matLeft, Right <= matRight.
     // tx >= matLeft + vidW/2
     // tx <= matRight - vidW/2
     
     final minTx = matLeft + vidW / 2.0;
     final maxTx = matRight - vidW / 2.0;
     final minTy = matTop + vidH / 2.0;
     final maxTy = matBottom - vidH / 2.0;
     
     // Apply Constraint (only if video fits; if video is somehow bigger than matrix, clamp to center?)
     // We already clamped scale, so video should fit (<= matrix).
     
     if (tx < minTx) tx = minTx;
     if (tx > maxTx) tx = maxTx;
     if (ty < minTy) ty = minTy;
     if (ty > maxTy) ty = maxTy;

     return MediaTransform(
       scaleX: scaleX,
       scaleY: scaleY,
       translateX: tx, // Clamped
       translateY: ty, // Clamped
       rotation: t.rotation,
       crop: t.crop
     );
  }
  Widget _buildSchedulerSection(ShowState state) {
      final schedule = state.currentShow?.schedule;
      if (schedule == null) return const SizedBox();

      return Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
            // Header + Toggle
            Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                  Row(
                     children: [
                        const Text("SCHEDULE", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                        const SizedBox(width: 8),
                        Tooltip(
                           message: "Location Settings (for Sunrise/Sunset)",
                           child: InkWell(
                              onTap: () => _showLocationDialog(context, state),
                              child: const Icon(Icons.location_on, size: 14, color: Colors.white24),
                           ),
                        ),
                     ],
                  ),
                  Container(
                     height: 28,
                     decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white24)
                     ),
                     child: Row(
                         children: [
                            // Always On
                            GestureDetector(
                               onTap: () => state.updateSchedule(schedule.copyWith(type: ScheduleType.indefinite)),
                               child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                     color: schedule.type == ScheduleType.indefinite ? Colors.cyan.withOpacity(0.2) : Colors.transparent,
                                     borderRadius: BorderRadius.circular(14)
                                  ),
                                  child: Icon(Icons.all_inclusive, size: 16, color: schedule.type == ScheduleType.indefinite ? Colors.cyanAccent : Colors.white38),
                               ),
                            ),
                            // Scheduled
                            GestureDetector(
                               onTap: () => state.updateSchedule(schedule.copyWith(type: ScheduleType.scheduled)),
                               child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                     color: schedule.type == ScheduleType.scheduled ? Colors.cyan.withOpacity(0.2) : Colors.transparent,
                                     borderRadius: BorderRadius.circular(14)
                                  ),
                                  child: Icon(Icons.schedule, size: 16, color: schedule.type == ScheduleType.scheduled ? Colors.cyanAccent : Colors.white38),
                               ),
                            ),
                         ],
                     ),
                  )
               ],
            ),
            
            if (schedule.type == ScheduleType.scheduled) ...[
               const SizedBox(height: 12),
               // Start Row
               _buildTimeRow("START", schedule.startTrigger, schedule.startTime, (trigger) {
                  state.updateSchedule(schedule.copyWith(startTrigger: trigger));
               }, (time) {
                  state.updateSchedule(schedule.copyWith(startTime: time));
               }),
               const SizedBox(height: 8),
               // End Row
               _buildTimeRow("END", schedule.endTrigger, schedule.endTime, (trigger) {
                  state.updateSchedule(schedule.copyWith(endTrigger: trigger));
               }, (time) {
                  state.updateSchedule(schedule.copyWith(endTime: time));
               }),
               const SizedBox(height: 12),
               
               // Days Row (Mon-Sun)
               Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(7, (index) {
                      final dayNames = ["M", "T", "W", "T", "F", "S", "S"];
                      final isEnabled = schedule.enabledDays[index];
                      return GestureDetector(
                         onTap: () {
                            List<bool> newDays = List.from(schedule.enabledDays);
                            newDays[index] = !isEnabled;
                            state.updateSchedule(schedule.copyWith(enabledDays: newDays));
                         },
                         child: Container(
                            width: 24, height: 24,
                            decoration: BoxDecoration(
                               shape: BoxShape.circle,
                               color: isEnabled ? Colors.cyan : Colors.transparent,
                               border: Border.all(color: isEnabled ? Colors.transparent : Colors.white24)
                            ),
                            alignment: Alignment.center,
                            child: Text(dayNames[index], style: TextStyle(color: isEnabled ? Colors.black : Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                         ),
                      );
                  }),
               )
            ]
         ],
      );
  }

  Widget _buildTimeRow(String label, ScheduleTrigger trigger, TimeOfDay time, Function(ScheduleTrigger) onTrigger, Function(TimeOfDay) onTime) {
      return Container(
         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
         decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8)
         ),
         child: Row(
            children: [
               Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
               const SizedBox(width: 12),
               // Trigger Dropdown
               DropdownButton<ScheduleTrigger>(
                  value: trigger,
                  dropdownColor: Colors.grey[900],
                  isDense: true,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white54),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  items: [
                     DropdownMenuItem(value: ScheduleTrigger.specific, child: Text("Time")),
                     DropdownMenuItem(value: ScheduleTrigger.sunrise, child: Text("Sunrise")),
                     DropdownMenuItem(value: ScheduleTrigger.sunset, child: Text("Sunset")),
                  ], 
                  onChanged: (val) {
                     if (val != null) onTrigger(val);
                  }
               ),
               const Spacer(),
               // Time Picker (If Specific)
               if (trigger == ScheduleTrigger.specific)
                  GestureDetector(
                     onTap: () => _pickTime(context, time, onTime),
                     child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                        child: Text(_formatTime(time), style: const TextStyle(color: Colors.cyanAccent, fontSize: 13, fontFamily: "Monospace"))
                     ),
                  )
               else
                  const Text("Astro", style: TextStyle(color: Colors.white24, fontSize: 11, fontStyle: FontStyle.italic))
            ],
         ),
      );
  }


  void _showLocationDialog(BuildContext context, ShowState state) {
      final schedule = state.currentShow?.schedule;
      if (schedule == null) return;

      final latCtrl = TextEditingController(text: (schedule.latitude ?? 40.7128).toString());
      final lngCtrl = TextEditingController(text: (schedule.longitude ?? -74.0060).toString());

      showDialog(
         context: context,
         builder: (ctx) {
            return AlertDialog(
               backgroundColor: const Color(0xFF252525),
               title: const Text("Location Settings", style: TextStyle(color: Colors.white)),
               content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     const Text("Required for correct Sunrise/Sunset calculations.", style: TextStyle(color: Colors.white54, fontSize: 12)),
                     const SizedBox(height: 16),
                     // Preset Dropdown
                     DropdownButtonFormField<String>(
                        dropdownColor: const Color(0xFF333333),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                           labelText: "Presets",
                           labelStyle: TextStyle(color: Colors.white54),
                           enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                           focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
                        ),
                        items: const [
                           DropdownMenuItem(value: "ny", child: Text("New York")),
                           DropdownMenuItem(value: "london", child: Text("London")),
                           DropdownMenuItem(value: "tokyo", child: Text("Tokyo")),
                           DropdownMenuItem(value: "paris", child: Text("Paris")),
                           DropdownMenuItem(value: "la", child: Text("Los Angeles")),
                           DropdownMenuItem(value: "sydney", child: Text("Sydney")),
                        ],
                        onChanged: (val) {
                           switch(val) {
                              case "ny": 
                                 latCtrl.text = "40.7128"; lngCtrl.text = "-74.0060"; break;
                              case "london": 
                                 latCtrl.text = "51.5074"; lngCtrl.text = "-0.1278"; break;
                              case "tokyo": 
                                 latCtrl.text = "35.6762"; lngCtrl.text = "139.6503"; break;
                              case "paris": 
                                 latCtrl.text = "48.8566"; lngCtrl.text = "2.3522"; break;
                              case "la": 
                                 latCtrl.text = "34.0522"; lngCtrl.text = "-118.2437"; break;
                              case "sydney": 
                                 latCtrl.text = "-33.8688"; lngCtrl.text = "151.2093"; break;
                           }
                        },
                     ),
                     const SizedBox(height: 16),
                     Row(
                        children: [
                           Expanded(
                              child: TextField(
                                 controller: latCtrl,
                                 style: const TextStyle(color: Colors.white),
                                 decoration: const InputDecoration(
                                    labelText: "Latitude",
                                    labelStyle: TextStyle(color: Colors.white54),
                                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
                                 ),
                                 keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                              ),
                           ),
                           const SizedBox(width: 8),
                           Expanded(
                              child: TextField(
                                 controller: lngCtrl,
                                 style: const TextStyle(color: Colors.white),
                                 decoration: const InputDecoration(
                                    labelText: "Longitude",
                                    labelStyle: TextStyle(color: Colors.white54),
                                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
                                 ),
                                 keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                              ),
                           ),
                        ],
                     ),
                  ],
               ),
               actions: [
                  TextButton(
                     onPressed: () => Navigator.pop(ctx),
                     child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
                  ),
                  TextButton(
                     onPressed: () {
                        final lat = double.tryParse(latCtrl.text);
                        final lng = double.tryParse(lngCtrl.text);
                        if (lat != null && lng != null) {
                           state.updateSchedule(schedule.copyWith(latitude: lat, longitude: lng));
                           Navigator.pop(ctx);
                        }
                     },
                     child: const Text("Save", style: TextStyle(color: Colors.greenAccent)),
                  ),
               ],
            );
         }
      );
  }
} // End _VideoTabState

class FixtureOverlayPainter extends CustomPainter {
  final List<Fixture> fixtures;
  FixtureOverlayPainter(this.fixtures);

  @override
  void paint(Canvas canvas, Size size) {
     final borderPaint = Paint()
       ..color = Colors.white24 // Setup Tab Outline
       ..style = PaintingStyle.stroke
       ..strokeWidth = 1.0;
       
     final pixelPaint = Paint()
       ..color = Colors.blue.withOpacity(0.3) // Setup Tab Pixels (Blueish)
       ..style = PaintingStyle.fill;

     for (var f in fixtures) {
         // Calculate Bounds
         const double kStride = 16.0; // 12px + 4px space
         final double w = f.width * kStride;
         final double h = f.height * kStride;
         
         canvas.save();
         // Translate to Center of Fixture for Rotation
         final double centerX = f.x + w / 2;
         final double centerY = f.y + h / 2;
         // Center Translation
         canvas.translate(centerX, centerY);
         if (f.rotation != 0) canvas.rotate(f.rotation * 3.14159 / 180);
         
         // Translate back to Top-Left of the fixture's local space
         canvas.translate(-w/2, -h/2);

         // Draw Container Border (Setup Tab Style)
         canvas.drawRect(Rect.fromLTWH(0, 0, w, h), borderPaint);

         // Draw Pixels
         const double pxSize = 12.0;
         const double pxSpace = 4.0;
         
         for (int y = 0; y < f.height; y++) {
            for (int x = 0; x < f.width; x++) {
               double left = x * (pxSize + pxSpace);
               double top = y * (pxSize + pxSpace);
               
               canvas.drawRect(Rect.fromLTWH(left, top, pxSize, pxSize), pixelPaint);
            }
         }
         
         canvas.restore();
     }
  }

  @override
  bool shouldRepaint(covariant FixtureOverlayPainter old) => old.fixtures != fixtures;
}

class PercentageClipper extends CustomClipper<Rect> {
  final CropInfo crop;
  PercentageClipper(this.crop);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(
      size.width * (crop.x / 100),
      size.height * (crop.y / 100),
      size.width * (crop.width / 100),
      size.height * (crop.height / 100),
    );
  }

  @override
  bool shouldReclip(covariant PercentageClipper oldClipper) {
    return oldClipper.crop.x != crop.x ||
        oldClipper.crop.y != crop.y ||
        oldClipper.crop.width != crop.width ||
        oldClipper.crop.height != crop.height;
  }
}