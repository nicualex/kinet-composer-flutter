import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'; // For ByteData
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/show_manifest.dart';
import '../../models/media_transform.dart';
import '../../state/show_state.dart';
import '../../services/effect_service.dart';
import '../../services/ffmpeg_service.dart';
import '../widgets/pixel_grid_painter.dart';
import '../widgets/transform_gizmo.dart';
import '../widgets/effect_renderer.dart';
import '../widgets/transfer_dialog.dart';
import '../widgets/layer_renderer.dart';
import '../../models/layer_config.dart';
import '../widgets/glass_container.dart';
import '../widgets/layer_controls.dart'; // Import new widget
import '../dialogs/render_dialog.dart'; // Import RenderDialog

// Enum removed, using from transform_gizmo.dart

class VideoTab extends StatefulWidget {
  const VideoTab({super.key});

  @override
  State<VideoTab> createState() => _VideoTabState();
}

class _VideoTabState extends State<VideoTab> {
  static const double kGridSize = 16.0;

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
  
  // REMOVED: bool _isEditingCrop = false;
  // REMOVED: MediaTransform? _tempTransform;
  
  // NEW: Intersection State for UI
  Rect? _currentIntersection;
  
  bool _isHoveringWorkspace = false; // NEW
  
  int _intersectW = 0;
  int _intersectH = 0;
  int _displayX = 0;
  int _displayY = 0;

  bool _isPlaying = false;
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
  EffectType? _selectedEffect;
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
     
     // 3. Apply
     WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ShowState>().updateLayer(
           target: targetLayer,
           transform: MediaTransform(
             scaleX: scale,
             scaleY: scale,
             translateX: 0,
             translateY: 0,
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
     if (_selectedEffect == null) return;

     final outputPath = await FilePicker.platform.saveFile(
       dialogTitle: 'Save Effect Video',
       fileName: 'effect_${_selectedEffect!.name}.mp4',
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
       // Use params from storage
       final show = context.read<ShowState>().currentShow;
       if (show == null) throw Exception("No show loaded");

       // final activeLayer = show.backgroundLayer; // TODO: or foreground? Effect export implies active?
       // _exportEffect logic currently uses _selectedEffect.
       // Let's assume we export the effect that is currently selected/edited.
       
        final filter = EffectService.getFFmpegFilter(
           _selectedEffect ?? EffectType.rainbow, 
           // Use active layer params
           (switch(_selectedLayer) {
              LayerTarget.background => show.backgroundLayer,
              LayerTarget.middle => show.middleLayer,
              LayerTarget.foreground => show.foregroundLayer,
           }).effectParams
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
               // Load it
               setState(() {
                 _selectedEffect = null; // Exit effect mode to view result
               });
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
              final jsonStr = await file.readAsString();
              final jsonMap = jsonDecode(jsonStr);
              
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
                  
                  // Force stop existing playback
                  await _bgPlayer.stop();
                  await _mdPlayer.stop();
                  await _fgPlayer.stop();
                  
                      _loadedBgPath = null;
                  _loadedMdPath = null;
                  _loadedFgPath = null;
                  
                  context.read<ShowState>().loadManifest(newShow);
                  
                  // Sync Controller
                  _nameController.text = newShow.name;
                  
                  setState(() {
                      // Check if any layer has active content (Video or Effect)
                      bool hasBg = newShow.backgroundLayer.type != LayerType.none;
                      bool hasMd = newShow.middleLayer.type != LayerType.none;
                      bool hasFg = newShow.foregroundLayer.type != LayerType.none;
                      
                      bool hasContent = hasBg || hasMd || hasFg;
                      
                      _isPlaying = hasContent; 
                      
                      // Auto-select the top-most active layer to ensure UI isn't empty
                      if (hasFg) {
                         _selectedLayer = LayerTarget.foreground;
                      } else if (hasMd) {
                         _selectedLayer = LayerTarget.middle;
                      } else if (hasBg) {
                         _selectedLayer = LayerTarget.background;
                      }
                  });
                  
                  // Trigger Sync to actually start playback if IsPlaying is true
                  _syncLayers(newShow);
                  
                  // Force intersection update for the new show's transforms
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _calculateIntersection();
                  });
                  
                  // Trigger Sync to actually start playback if IsPlaying is true
                  _syncLayers(newShow);

                   ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text("Show loaded successfully"), backgroundColor: Colors.green)
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
         _isPlaying = false;
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
      if (_isPlaying) {
         _bgPlayer.pause();
         _mdPlayer.pause();
         _fgPlayer.pause();
         setState(() => _isPlaying = false);
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
    final show = context.read<ShowState>().currentShow;
    if (show == null || show.fixtures.isEmpty) return;

    // Use Active Player dimensions OR Default for Effects
    LayerConfig activeLayer = switch(_selectedLayer) {
       LayerTarget.background => show.backgroundLayer,
       LayerTarget.middle => show.middleLayer,
       LayerTarget.foreground => show.foregroundLayer,
    };
    final size = _resolveLayerSize(show, activeLayer);
    final width = size.width;
    final height = size.height;

    if (width <= 0 || height <= 0) return;
    
    // Force Aspect Ratio Lock to TRUE on Reset/Fit
    context.read<ShowState>().updateLayer(target: _selectedLayer, lockAspectRatio: true);
    
    // 1. Calculate Matrix Bounds in "Pixel" space
    final bounds = _calculateMatrixBounds(show);
    double matW = bounds.width;
    double matH = bounds.height;
    
    // 2. Calculate Required Scale
    // Video Size Visual = VideoPx * Scale
    
    double targetScaleX = 1.0;
    double targetScaleY = 1.0;
    
    // Logic: Effects always Stretch. Videos check Lock.
    final hasActiveEffect = activeLayer.type == LayerType.effect;
    
    // On Fit/Reset, we treat Aspect as LOCKED (Contain) unless Effect (Stretch)
    if (hasActiveEffect) {
       // STRETCH: Visual Size == Matrix Size
       targetScaleX = matW / width;
       targetScaleY = matH / height;
    } else {
       // CONTAIN (Fit Inside)
       // User reported overflows with Cover mode. Reverting to Contain.
       // "Contain" = Min(MatrixW / VideoW, MatrixH / VideoH). Ensures ENTIRE video is visible.
       double rX = matW / width;
       double rY = matH / height;
       double scale = (rX < rY) ? rX : rY; // MIN for Contain
       targetScaleX = scale;
       targetScaleY = scale;
    }
    
    // 3. Apply Transform
    context.read<ShowState>().updateLayer(
      target: _selectedLayer, 
      transform: MediaTransform(
         scaleX: targetScaleX,
         scaleY: targetScaleY,
         translateX: 0,
         translateY: 0,
         rotation: 0,
         crop: null,
      )
    );
       
    // Update Intersection immediately
    _calculateIntersection();
    
    debugPrint("Auto-Fit Applied");
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Auto-Fit Applied"), duration: Duration(milliseconds: 500)));
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
         // Handle Rotation
         bool isRotated = (f.rotation % 180) != 0;
         double actualW = isRotated ? fh : fw;
         double actualH = isRotated ? fw : fh;
         
         double fx = f.x; // Position is already in pixels
         double fy = f.y; // Position is already in pixels
         
         if (fx < minMx) minMx = fx;
         if (fx + actualW > maxMx) maxMx = fx + actualW;
         if (fy < minMy) minMy = fy;
         if (fy + actualH > maxMy) maxMy = fy + actualH;
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

          return Row(
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
                         Container(
                           margin: const EdgeInsets.only(bottom: 16),
                           padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                           decoration: BoxDecoration(
                             color: Colors.white10,
                             borderRadius: BorderRadius.circular(8),
                             border: Border.all(color: Colors.white24)
                           ),
                           child: TextField(
                             controller: _nameController,
                             textAlign: TextAlign.center,
                             style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                             decoration: const InputDecoration(
                               border: InputBorder.none,
                               contentPadding: EdgeInsets.zero,
                               isDense: true,
                             ),
                             cursorColor: Colors.white,
                             onChanged: (value) {
                                 if (value.isNotEmpty) {
                                   context.read<ShowState>().updateName(value);
                                 }
                             },
                           ),
                         ),
                         
                         // 2. File Actions
                         Row(
                           children: [
                             Expanded(child: _buildIconFn(Icons.folder_open, "Load Show", Colors.white70, () => _loadShow())),
                             const SizedBox(width: 8),
                             Expanded(child: _buildIconFn(Icons.save, "Save Show", Colors.white70, 
                                 show.backgroundLayer.type != LayerType.none || show.middleLayer.type != LayerType.none || show.foregroundLayer.type != LayerType.none 
                                 ? () => _saveShow() : null)),
                           ],
                         ),
                         const SizedBox(height: 8),
                         Row(
                           children: [
                              Expanded(child: _buildIconFn(Icons.add_to_photos, "Load Media", const Color(0xFF90CAF9), () => _pickVideo(context))),
                              const SizedBox(width: 8),
                              Expanded(child: _buildIconFn(Icons.movie_creation, "Render", const Color(0xFFA5D6A7), 
                                 show.backgroundLayer.type != LayerType.none || show.middleLayer.type != LayerType.none || show.foregroundLayer.type != LayerType.none 
                                 ? () => _renderVideo() : null)),
                           ],
                         ),
                         const SizedBox(height: 8), 
                         Center(
                            child: TextButton.icon(
                              onPressed: _initializeShow,
                              icon: const Icon(Icons.refresh, color: Colors.white38, size: 16),
                              label: const Text("INITIALIZE SHOW", style: TextStyle(color: Colors.white38, fontSize: 10)),
                              style: TextButton.styleFrom(
                                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                 backgroundColor: Colors.white.withOpacity(0.05),
                              ),
                            ),
                          ),
                         const SizedBox(height: 24),
  
                         // 3. Layer Controls
                         Text("LAYERS", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                         const SizedBox(height: 12),
                         LayerControls(
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
                                    if (nextLayer.type == LayerType.effect && nextLayer.effect != null) {
                                        _selectedEffect = nextLayer.effect;
                                    } else {
                                        _selectedEffect = null;
                                    }
                                    _calculateIntersection();
                                 });
                              }
                           },
                         ),
                         const SizedBox(height: 24),

                         // 4. Matrix Intersection
                         if (activeLayer.type != LayerType.none) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                 color: Colors.white10,
                                 borderRadius: BorderRadius.circular(8),
                                 border: Border.all(color: Colors.white24)
                              ),
                              child: Column(
                                 crossAxisAlignment: CrossAxisAlignment.start,
                                 children: [
                                    Text("MATRIX INTERSECTION", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    if (_currentIntersection != null) ...[
                                        _buildInfoRow("X Start", "$_displayX"),
                                        _buildInfoRow("Width", "$_intersectW px"),
                                        _buildInfoRow("Y Start", "$_displayY"),
                                        _buildInfoRow("Height", "$_intersectH px"),
                                    ] else 
                                       const Text("No Intersection / No Matrix", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                                 ],
                              ),
                            ),
                            const SizedBox(height: 24),
                         ],

                        const Divider(color: Colors.white10, height: 1),
                        const SizedBox(height: 24),

                        // 5. Media Controls
                        Text("CONTROLS", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                           children: [
                             // Play/Pause
                             Expanded(
                               child: InkWell(
                                 onTap: () {
                                    if (_isPlaying) {
                                      _bgPlayer.pause(); _mdPlayer.pause(); _fgPlayer.pause();
                                    } else {
                                      _bgPlayer.play(); _mdPlayer.play(); _fgPlayer.play();
                                    }
                                    setState(() => _isPlaying = !_isPlaying);
                                 },
                                 child: Container(
                                   padding: const EdgeInsets.symmetric(vertical: 12),
                                   decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                                   child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                                 ),
                               ),
                             ),
                             const SizedBox(width: 8),
                             // Stop
                             Expanded(
                               child: InkWell(
                                 onTap: () async {
                                   await _bgPlayer.seek(Duration.zero); await _mdPlayer.seek(Duration.zero); await _fgPlayer.seek(Duration.zero);
                                   await _bgPlayer.pause(); await _mdPlayer.pause(); await _fgPlayer.pause();
                                   setState(() => _isPlaying = false);
                                 },
                                 child: Container(
                                   padding: const EdgeInsets.symmetric(vertical: 12),
                                   decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                                   child: const Icon(Icons.stop, color: Colors.redAccent),
                                 ),
                               ),
                             ),
                             const SizedBox(width: 8),
                             // Aspect Ratio Lock
                             Expanded(
                               child: InkWell(
                                 onTap: activeLayer.type == LayerType.video ? () {
                                    context.read<ShowState>().updateLayer(
                                      target: _selectedLayer,
                                      lockAspectRatio: !activeLayer.lockAspectRatio
                                    );
                                 } : null,
                                 child: Container(
                                   padding: const EdgeInsets.symmetric(vertical: 12),
                                   decoration: BoxDecoration(
                                     color: activeLayer.lockAspectRatio && activeLayer.type == LayerType.video ? const Color(0xFF1565C0) : Colors.white10, 
                                     borderRadius: BorderRadius.circular(8),
                                     border: Border.all(color: activeLayer.type == LayerType.video ? Colors.transparent : Colors.transparent)
                                   ),
                                   child: Icon(
                                     activeLayer.lockAspectRatio ? Icons.lock : Icons.lock_open, 
                                     color: activeLayer.type == LayerType.video ? (activeLayer.lockAspectRatio ? Colors.white : Colors.white54) : Colors.white24,
                                     size: 20
                                   ),
                                 ),
                               ),
                             ),
                           ],
                        ),
                        const SizedBox(height: 24),

                        // 6. Effects
                          if (_selectedEffect != null) ...[
                             Row(
                               key: ValueKey("EffectSettingsHeader_${_selectedEffect}"),
                               children: [
                                  Expanded(
                                    child: Text(
                                      _selectedEffect!.name.toUpperCase(), 
                                      style: const TextStyle(color: Color(0xFFA5D6A7), fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () {
                                           context.read<ShowState>().updateLayer(
                                              target: _selectedLayer,
                                              type: LayerType.none,
                                              effect: null
                                           );
                                           setState(() {
                                              _selectedEffect = null;
                                           });
                                        },
                                        icon: const Icon(Icons.delete, size: 14, color: Colors.redAccent),
                                        label: const Text("DELETE", style: TextStyle(color: Colors.redAccent, fontSize: 10)),
                                        style: TextButton.styleFrom(
                                           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                           backgroundColor: Colors.redAccent.withOpacity(0.1),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton.icon(
                                        onPressed: () {
                                           setState(() {
                                              _selectedEffect = null;
                                           });
                                        },
                                        icon: const Icon(Icons.check, size: 14, color: Colors.greenAccent),
                                        label: const Text("DONE", style: TextStyle(color: Colors.greenAccent, fontSize: 10)),
                                        style: TextButton.styleFrom(
                                           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                           backgroundColor: Colors.greenAccent.withOpacity(0.1),
                                        ),
                                      ),
                                    ],
                                  )
                               ],
                             ),
                             const SizedBox(height: 12),
                              

                            
                            Column(
                                key: ValueKey("EffectParams_${_selectedEffect}"),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    ...activeParams.entries.map((entry) {
                                       final key = entry.key;
                                       dynamic value = entry.value;

                                       return Padding(
                                         padding: const EdgeInsets.only(bottom: 12.0),
                                         child: Column(
                                           crossAxisAlignment: CrossAxisAlignment.start,
                                           children: [
                                             Text(key.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                                             const SizedBox(height: 4),
                                             
                                             // 1. Color Picker
                                             if (key.toLowerCase().contains('color') && (value is int)) ...[
                                                 GestureDetector(
                                                   onTap: () {
                                                      showDialog(
                                                        context: context,
                                                        builder: (c) => AlertDialog(
                                                          title: const Text("Pick Color"),
                                                          content: SingleChildScrollView(
                                                            child: ColorPicker(
                                                              pickerColor: Color(value),
                                                              onColorChanged: (c) {
                                                                 // Update immediately? Or on end?
                                                                 // Let's update on end to avoid spam, but ColorPicker usually needs state.
                                                                 // We'll update state directly.
                                                                 final newParams = Map<String, dynamic>.from(activeParams);
                                                                 newParams[key] = c.value;
                                                                 context.read<ShowState>().updateLayer(
                                                                    target: _selectedLayer, 
                                                                    params: newParams
                                                                 );
                                                              },
                                                              enableAlpha: false,
                                                              displayThumbColor: true,
                                                              paletteType: PaletteType.hsvWithHue,
                                                            ),
                                                          ),
                                                          actions: [
                                                            TextButton(onPressed: () => Navigator.pop(c), child: const Text("Done"))
                                                          ],
                                                        )
                                                      );
                                                   },
                                                   child: Container(
                                                     height: 40,
                                                     decoration: BoxDecoration(
                                                       color: Color(value),
                                                       borderRadius: BorderRadius.circular(8),
                                                       border: Border.all(color: Colors.white24)
                                                     ),
                                                   ),
                                                 )
                                             
                                             // 2. Text Input
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
                                                       final newParams = Map<String, dynamic>.from(activeParams);
                                                       newParams[key] = v;
                                                       context.read<ShowState>().updateLayer(
                                                          target: _selectedLayer, 
                                                          params: newParams
                                                       );
                                                    },
                                                 )

                                             // 3. Slider (Double)
                                             ] else if (value is num) ...[
                                                 Builder(builder: (context) {
                                                    final def = EffectService.effects.firstWhere((e) => e.type == _selectedEffect);
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
                                                                  final newParams = Map<String, dynamic>.from(activeParams);
                                                                  newParams[key] = v;
                                                                  context.read<ShowState>().updateLayer(
                                                                     target: _selectedLayer, 
                                                                     params: newParams
                                                                  );
                                                               },
                                                             ),
                                                           ),
                                                         ),
                                                         Text(dVal.toStringAsFixed(1), style: const TextStyle(color: Colors.white54, fontSize: 10)),
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
                        ] else ...[
                            Text("EFFECTS LIBRARY", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Wrap(
                               key: const ValueKey("EffectsLibraryWrap"),
                               spacing: 8,
                               runSpacing: 8,
                               children: EffectService.effects.map((e) {
                                   return SizedBox(
                                      width: 52, // Approx 320 / 5 - spacing
                                      height: 52,
                                      child: InkWell(
                                          onTap: () {
                                            // 1. Calculate Scale to Fit Matrix
                                            final show = context.read<ShowState>().currentShow;
                                            double scaleX = 1.0;
                                            double scaleY = 1.0;
                                            
                                            if (show != null && show.fixtures.isNotEmpty) {
                                                double minMx = double.infinity, maxMx = double.negativeInfinity;
                                                double minMy = double.infinity, maxMy = double.negativeInfinity;
                                                for (var f in show.fixtures) {
                                                   double fw = f.width * kGridSize;
                                                   double fh = f.height * kGridSize;
                                                   // Handle Rotation (Swap W/H if 90/270)
                                                   bool isRotated = (f.rotation % 180) != 0;
                                                   double actualW = isRotated ? fh : fw;
                                                   double actualH = isRotated ? fw : fh;
                                                   
                                                   double fx = f.x;
                                                   double fy = f.y;
                                                   
                                                   if (fx < minMx) minMx = fx;
                                                   if (fx + actualW > maxMx) maxMx = fx + actualW;
                                                   if (fy < minMy) minMy = fy;
                                                   if (fy + actualH > maxMy) maxMy = fy + actualH;
                                                }
                                                maxMx += kGridSize; 
                                                maxMy += kGridSize;
                                                
                                                double matW = maxMx - minMx;
                                                double matH = maxMy - minMy;
                                                
                                                // Default Effect Size is 1920x1080
                                                scaleX = matW / 1920.0;
                                                scaleY = matH / 1080.0;
                                            }

                                            context.read<ShowState>().updateLayer(
                                               target: _selectedLayer,
                                               type: LayerType.effect,
                                               effect: e.type,
                                               opacity: 1.0, 
                                               params: e.defaultParams,
                                               transform: MediaTransform(
                                                  scaleX: scaleX, 
                                                  scaleY: scaleY, 
                                                  translateX: 0, 
                                                  translateY: 0, 
                                                  rotation: 0
                                               )
                                            );
                                            setState(() {
                                              _selectedEffect = e.type;
                                              _isPlaying = true;
                                            });
                                            
                                            // Trigger intersection update
                                            WidgetsBinding.instance.addPostFrameCallback((_) {
                                                if (mounted) _calculateIntersection();
                                            });
                                          },
                                          child: Tooltip(
                                            message: e.name, 
                                            child: Container(
                                               decoration: BoxDecoration(
                                                  color: Colors.black,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: _selectedEffect == e.type 
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
                                   );
                               }).toList(),
                             ),
                          ],
                    ],
                  ),
                ),
              ), 

              // Main Content Area
              Expanded(
                 child: Container(
                   color: Colors.black, // Fix: Black Background
                   child: ClipRect(
                     child: LayoutBuilder(
                       builder: (context, constraints) {
                          // 1. Calculate Matrix Bounds (Logical 10.0 scale)
                          final show = context.read<ShowState>().currentShow;
                          if (show == null) return const SizedBox();

                          double minX = double.infinity, maxX = double.negativeInfinity;
                          double minY = double.infinity, maxY = double.negativeInfinity;
                          bool hasFixtures = show.fixtures.isNotEmpty;
                          
                          if (hasFixtures) {
                             for (var f in show.fixtures) {
                               double fw = f.width * kGridSize;
                               double fh = f.height * kGridSize;
                               // Handle Rotation (Swap W/H if 90/270)
                               bool isRotated = (f.rotation % 180) != 0;
                               double actualW = isRotated ? fh : fw;
                               double actualH = isRotated ? fw : fh;
                               
                               double fx = f.x;
                               double fy = f.y;
                               
                               if (fx < minX) minX = fx;
                               if (fx + actualW > maxX) maxX = fx + actualW;
                               if (fy < minY) minY = fy;
                               if (fy + actualH > maxY) maxY = fy + actualH;
                             }
                             // No need to add gridSize separately as W/H covers it
                             // maxX += gridSize; 
                             // maxY += gridSize;
                          } else {
                            minX = 0; maxX = 1000;
                            minY = 0; maxY = 1000;
                          }
                          
                          double matW = maxX - minX;
                          double matH = maxY - minY;
                          if (matW <= 0) matW = 1000;
                          if (matH <= 0) matH = 1000;
                          
                          return Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: FittedBox(
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                              child: Container(
                              width: matW,
                              height: matH,
                              color: Colors.transparent,
                               child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: [
                                   // REFACTORED STACK Z-ORDER WITH GIZMO
                                   ..._buildLayerStack(show, matW, matH),
 
                                   // LAYER 2: Matrix (Localized) - OVERLAY
                                   if (hasFixtures)
                                     Positioned(
                                       left: -minX, 
                                       top: -minY,
                                       child: IgnorePointer(
                                         child: CustomPaint(
                                           size: Size(matW, matH),
                                           painter: PixelGridPainter(
                                              fixtures: show.fixtures, 
                                              drawLabels: false,
                                              gridSize: kGridSize
                                           ),
                                         ),
                                       ),
                                     ),
                                ],
                               ),
                              ),
                            ),
                          );
                       },
                     ),
                   ),
                 ),
              ),
           ],
        );
  }
      );
  }
  void _calculateIntersection() {
    final show = context.read<ShowState>().currentShow;
    if (show == null) return;
    
    LayerConfig activeLayer = switch(_selectedLayer) {
       LayerTarget.background => show.backgroundLayer,
       LayerTarget.middle => show.middleLayer,
       LayerTarget.foreground => show.foregroundLayer,
    };
    final transform = activeLayer.transform ?? MediaTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0);

    final size = _resolveLayerSize(show, activeLayer);
    final width = size.width;
    final height = size.height;
    
    if (show.fixtures.isEmpty || width <= 0 || height <= 0) {
       if (_currentIntersection != null) {
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
    // We center the matrix visually, so the coordinate system for intersection 
    // should be relative to the Center of the matrix bounds.
    // _calculateMatrixBounds returns Absolute coordinates (e.g. 100,100 to 200,200).
    // The Visual Stack is size matW x matH.
    // Fixtures are drawn at (f.x - minMx, f.y - minMy).
    // So Visual (0,0) corresponds to Absolute (minMx, minMy).
    // The 'videoRect' is calculated relative to Center of the Stack.
    // Stack Center = (matW/2, matH/2).
    
    // Actually, earlier Visual Logic:
    // Stack(alignment: Alignment.center)
    // Layer(Center(Transform(Video))). Video (0,0) is at Stack Center.
    // Overlay(Positioned(left: -minX, top: -minY, CustomPaint)).
    // Painter(0,0) is at Stack TopLeft - (minX, minY).
    // Fixture(fx, fy) draws at Painter(fx, fy).
    // On Screen relative to Stack TopLeft: (fx - minX, fy - minY).
    // Stack Center relative to Stack TopLeft: (matW/2, matH/2).
    // Fixture relative to Stack Center: (fx - minX - matW/2, fy - minY - matH/2).
    
    // WE NEED 'matrixRect' in coordinates relative to Stack Center.
    // Current code: Rect matrixRect = Rect.fromCenter(center: Offset.zero, width: matW, height: matH);
    // This assumes the Matrix fills the Stack and is centered.
    // Since matW = maxMx - minMx.
    // Left edge (relative to center) = -matW/2.
    // Right edge = matW/2.
    // Visual Left Edge = minX.
    // fixture at minX -> Screen X = minX - minX = 0.
    // 0 relative to Center = -matW/2.
    // So yes, the Matrix Bounds map exactly to Rect.fromCenter(0,0, matW, matH).
    // The previous manual logic was just calculating matW wrong.
    // Now that we use _calculateMatrixBounds, matW should be correct.
    
    // 2. Video Bounds (Logic Space) relative to Matrix Center
    // Matrix is centered at (0,0) visually.
    // Video is transformed relative to (0,0).
    
    // Use the 'transform' variable defined earlier
    // final t = show.mediaTransform ?? MediaTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0);
    
    // Video Original Size
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
    
    // Matrix Rect relative to Center (0,0)
    // Matrix Center is (minMx + maxMx)/2, (minMy + maxMy)/2
    // But we draw Matrix so that it fits in the container centered.
    // Matrix spans from -matW/2 to matW/2 relative to center.
    
    Rect matrixRect = Rect.fromCenter(center: Offset.zero, width: matW, height: matH);
    
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

       setState(() {
          _currentIntersection = intersect;
          _intersectW = w;
          _intersectH = h;
          _displayX = dX;
          _displayY = dY;
       });
    } else {
       if (_currentIntersection != null) {
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

  // MARK: - Layer Rendering
  
   List<Widget> _buildLayerStack(ShowManifest show, double matW, double matH) {
     return [
        _buildStackedLayer(LayerTarget.background, show.backgroundLayer, matW, matH),
        _buildStackedLayer(LayerTarget.middle, show.middleLayer, matW, matH),
        _buildStackedLayer(LayerTarget.foreground, show.foregroundLayer, matW, matH),
     ];
  }

  Widget _buildStackedLayer(LayerTarget target, LayerConfig layer, double matW, double matH) {
      if (layer.type == LayerType.none) return const SizedBox();
      
      // If we are selecting this layer, we wrap it in Gizmo.
      // If NOT, we wrap in IgnorePointer so touches fall through to BG if needed?
      // Actually, if FG is visible (Alpha/Effect), and I select BG...
      // I want to see BG overlay/Gizmo? 
      // Gizmo draws handles. If FG is opaque, I can't see BG handles?
      // Gizmo handles are usually drawn outside/edges.
      
      if (_selectedLayer == target) {
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

      return TransformGizmo(
        key: ValueKey("gizmo_$target"),
        transform: layer.transform ?? const MediaTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0),
        isSelected: true,
        lockAspect: layer.type == LayerType.video ? layer.lockAspectRatio : false,
        onUpdate: (newT) {
           final constrained = _constrainTransform(newT, layer, Size(matW, matH));
           context.read<ShowState>().updateLayer(
              target: target,
              transform: constrained
           );
           _calculateIntersection();
        },
        onDoubleTap: () {
           debugPrint("Double Tap on Layer $target -> Auto-Fit");
           _fitToMatrix();
        },
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
                 child: EffectRenderer(type: layer.effect, params: layer.effectParams, isPlaying: _isPlaying)
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
          _isPlaying = true;
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
  MediaTransform _constrainTransform(MediaTransform t, LayerConfig layer, Size matrixSize) {
     final layerSize = _resolveLayerSize(context.read<ShowState>().currentShow!, layer);
     
     // 1. Clamp Scale (Max Size = Matrix Size)
     // Ensure video/effect doesn't exceed matrix bounds
     
     double scaleX = t.scaleX;
     double scaleY = t.scaleY;
     
     final maxSX = matrixSize.width / layerSize.width;
     final maxSY = matrixSize.height / layerSize.height;
     
     bool isLocked = layer.type == LayerType.video ? layer.lockAspectRatio : false; // Effects unlocked
     
     if (isLocked) {
         // If locked, we must maintain aspect ratio.
         // If EITHER dimension exceeds limit, we clamp BOTH.
         // Wait. TransformGizmo drives the scale.
         // If current scale > max, we clamp.
         // We use the most restrictive limit.
         // Actually, if we hit X limit, we clamp X, and Y follows.
         
         double factor = 1.0;
         if (scaleX > maxSX) factor = maxSX / scaleX;
         if (scaleY * factor > maxSY) factor = (maxSY / scaleY) * factor; // Re-clamp if Y still too big
         
         // Only apply if factor < 1 (reduction)
         // Wait. If scale is valid, factor is 1.
         // If scale is too big, factor < 1.
         // We also don't want to force it to be MAX if user wants SMALL.
         // So we only clamp MAX.
         
         if (factor < 1.0) {
             scaleX *= factor;
             scaleY *= factor;
         }
     } else {
         // Unlocked: Clamp independently
         if (scaleX > maxSX) scaleX = maxSX;
         if (scaleY > maxSY) scaleY = maxSY;
     }

     // 2. Clamp Translation (Pan)
     // Re-calc dimensions with clamped scale
     double vidW = layerSize.width * scaleX;
     double vidH = layerSize.height * scaleY;
     
     // Limit = Half of the difference
     double limitX = (matrixSize.width - vidW).abs() / 2;
     double limitY = (matrixSize.height - vidH).abs() / 2;
     
     double tx = t.translateX;
     double ty = t.translateY;
     
     if (tx < -limitX) tx = -limitX;
     if (tx > limitX) tx = limitX;
     if (ty < -limitY) ty = -limitY;
     if (ty > limitY) ty = limitY;
     
     return MediaTransform(
       scaleX: scaleX,
       scaleY: scaleY,
       translateX: tx,
       translateY: ty,
       rotation: t.rotation,
       crop: t.crop
     );
  }
} // End _VideoTabState

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