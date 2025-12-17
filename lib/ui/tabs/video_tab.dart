import 'dart:async';
import 'dart:io';

import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'; // For ByteData
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../models/show_manifest.dart';
import '../../models/media_transform.dart';
import '../../state/show_state.dart';
import '../../services/effect_service.dart';
import '../widgets/pixel_grid_painter.dart';
import '../widgets/transform_gizmo.dart';
import '../widgets/effect_renderer.dart';
import '../widgets/transfer_dialog.dart';
import '../widgets/layer_renderer.dart';
import '../../models/layer_config.dart';
import '../widgets/glass_container.dart';

// Enum removed, using from transform_gizmo.dart

class VideoTab extends StatefulWidget {
  const VideoTab({super.key});

  @override
  State<VideoTab> createState() => _VideoTabState();
}

class _VideoTabState extends State<VideoTab> {
  late final Player _bgPlayer;
  late final VideoController _bgController;
  late final Player _fgPlayer;
  late final VideoController _fgController;
  

  
  bool _isForegroundSelected = false; // False = Background, True = Foreground
  
  // REMOVED: bool _isEditingCrop = false;
  // REMOVED: MediaTransform? _tempTransform;
  
  // NEW: Intersection State for UI
  Rect? _currentIntersection;
  int _intersectW = 0;
  int _intersectH = 0;
  int _displayX = 0;
  int _displayY = 0;

  bool _isPlaying = false;
  late final StreamSubscription<bool> _playingSubscription;

  bool _pendingAutoFit = false;
  late final StreamSubscription<int?> _widthSubscription;
  late final StreamSubscription<int?> _heightSubscription;

  // NEW: Aspect Ratio Lock State
  bool _lockAspectRatio = true;
  // REMOVED: EditMode _editMode = EditMode.zoom;

  // NEW: Effects State
  EffectType? _selectedEffect;
  // REMOVED: Map<String, double> _effectParams = {};
  
  final GlobalKey _previewKey = GlobalKey(); // For Snapshot
  


  @override
  void initState() {
    super.initState();
    _bgPlayer = Player();
    _bgController = VideoController(_bgPlayer);
    
    _fgPlayer = Player();
    _fgController = VideoController(_fgPlayer);
    
    _playingSubscription = _bgPlayer.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          _isPlaying = playing;
        });
      }
    });

    // Auto-Fit Listener (On Background Video)
    _widthSubscription = _bgPlayer.stream.width.listen((w) => _checkAutoFit());
    _heightSubscription = _bgPlayer.stream.height.listen((h) => _checkAutoFit());
  }
  
  void _checkAutoFit() {
     if (!_pendingAutoFit) return;
     
     final w = _bgPlayer.state.width;
     final h = _bgPlayer.state.height;
     
     if (w != null && h != null && w > 0 && h > 0) {
        _autoFitVideoToMatrix(w, h);
        _pendingAutoFit = false;
     }
  }

  void _autoFitVideoToMatrix(int videoW, int videoH) {
     final show = context.read<ShowState>().currentShow;
     if (show == null || show.fixtures.isEmpty) return;

     // 1. Calculate Matrix Bounds (pixels)
     double boundsW = 0;
     double boundsH = 0;
     const double gridSize = 10.0;
     
     for (var f in show.fixtures) {
        double fw = f.width * gridSize;
        double fh = f.height * gridSize;
        if (fw > boundsW) boundsW = fw;
        if (fh > boundsH) boundsH = fh;
     }
     
     if (boundsW == 0 || boundsH == 0) return;

     // 2. Calculate Scale required to FIT VIDEO INSIDE matrix (Contain)
     // "both x and y should fit" implies we fully show the video.
     double scaleX = boundsW / videoW;
     double scaleY = boundsH / videoH;
     
     // Use the smaller scale to ensure the video fits entirely within the matrix bounds
     // (leaving empty space if aspect ratios differ, i.e., "parts of matrix not covered")
     double scale = (scaleX < scaleY) ? scaleX : scaleY;
     
     // Optional: Add a little padding or precise match?
     // Precise match is better for mapping.

     // 3. Center it?
     // Default video position is centered in the view.
     // Default matrix position is (0,0) in the grid painter to (maxW, maxH).
     // Ideally we want 0,0 of video to align with 0,0 of matrix if we scaled it?
     // Video is drawn centered. Matrix is drawn centered.
     // So if we just scale it, they should align if their centers align.
     
     WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ShowState>().updateTransform(MediaTransform(
           scaleX: scale,
           scaleY: scale,
           translateX: 0,
           translateY: 0,
           rotation: 0
        ));
        
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("Auto-scaled video to match matrix (Scale: ${scale.toStringAsFixed(2)}x)"), duration: const Duration(seconds: 1))
        );
     });
  }

  @override
  void dispose() {
    _playingSubscription.cancel();
    _widthSubscription.cancel();
    _heightSubscription.cancel();
    _bgPlayer.dispose();
    _fgPlayer.dispose();
    super.dispose();
  }

  Future<void> _pickVideo(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      dialogTitle: 'Select Video File (${_isForegroundSelected ? "Foreground" : "Background"})',
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      if (context.mounted) {
         context.read<ShowState>().updateLayer(
            isForeground: _isForegroundSelected,
            type: LayerType.video,
            path: path
         );
      }
    }
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
       final activeLayer = show.backgroundLayer; // TODO: or foreground? Effect export implies active?
       // _exportEffect logic currently uses _selectedEffect.
       // Let's assume we export the effect that is currently selected/edited.
       
        final filter = EffectService.getFFmpegFilter(
           _selectedEffect ?? EffectType.rainbow, 
           // _effectParams was removed. Use active layer params.
           // Which layer? _selectedEffect implies we are editing one.
           (_isForegroundSelected ? show.foregroundLayer : show.backgroundLayer).effectParams
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



  Future<void> _exportVideo() async {
    final show = context.read<ShowState>().currentShow;
    if (show == null || show.mediaFile.isEmpty) return;

     // Must have intersection to export
     if (_currentIntersection == null || _intersectW <= 0 || _intersectH <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No Intersection with Matrix! Move video over matrix to export.")));
        return;
     }

     // TODO: Support exporting composition of both layers?
     // For now, export background layer if it's a video.
     if (show.backgroundLayer.type != LayerType.video || show.backgroundLayer.path == null) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Background layer is not a video. Export not supported yet.")));
         return;
     }
     
     final sourcePath = show.backgroundLayer.path!;

    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Exported Video',
      fileName: 'exported_video.mp4',
      type: FileType.video,
      allowedExtensions: ['mp4'],
    );

    if (outputPath == null) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text("Exporting Video..."),
            const SizedBox(height: 10),
            Text("Resolution: ${_intersectW}x${_intersectH}\nRegion: ${_currentIntersection!.left.toStringAsFixed(0)},${_currentIntersection!.top.toStringAsFixed(0)} to ${_currentIntersection!.right.toStringAsFixed(0)},${_currentIntersection!.bottom.toStringAsFixed(0)}", 
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );

    try {
      final baseT = show.backgroundLayer.transform ?? MediaTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0);
      final t = baseT;
      
       final width = _bgPlayer.state.width;
       final height = _bgPlayer.state.height;

      // 1. Calculate Source Crop based on Intersection
      // The intersection is in "Visual Logic Space" (where GridSize is 10.0)
      // We need to map this back to Video Source Pixels.
      
      // Video Visual Rect (Logic Space)
      // Center at tx, ty. Size w*sx, h*sy.
      final scaledW = (width ?? 1920) * t.scaleX;
      final scaledH = (height ?? 1080) * t.scaleY;
      final vidLeft = t.translateX - (scaledW / 2);
      final vidTop = t.translateY - (scaledH / 2);
      
      // Relative Crop in Visual Units from Video Left/Top
      double cropVisX = _currentIntersection!.left - vidLeft;
      double cropVisY = _currentIntersection!.top - vidTop;
      
      // Clamp (floating point drift)
      if (cropVisX < 0) cropVisX = 0;
      if (cropVisY < 0) cropVisY = 0;
      
      double cropVisW = _currentIntersection!.width;
      double cropVisH = _currentIntersection!.height;
      
      // 2. Map Visual Crop to Source Pixels
      // Ratio = Source / Visual
      // Source W / Scaled W = 1 / Scale
      
      double sourceX = cropVisX / t.scaleX;
      double sourceY = cropVisY / t.scaleY;
      double sourceW = cropVisW / t.scaleX;
      double sourceH = cropVisH / t.scaleY;
      
      // Ensure we don't exceed source bounds
      if (sourceX + sourceW > (width ?? 1920)) sourceW = (width ?? 1920) - sourceX;
      if (sourceY + sourceH > (height ?? 1080)) sourceH = (height ?? 1080) - sourceY;
      
      // 3. Construct FFmpeg Filter Chain
      List<String> filters = [];
      
      // A. Crop Source
      filters.add('crop=${sourceW.floor()}:${sourceH.floor()}:${sourceX.floor()}:${sourceY.floor()}');
      
      // B. Scale to Target Resolution (Matrix Size)
      // Ideally sourceW should verify to match targetW * 10.0 / scale?
      // Yes. Visual Size = Source * Scale. Grid Size = Visual / 10.
      // Target Res = Grid Size.
      // So Source -> Scale -> Target.
      
      // We crop first (in source pixels). Then scale that cropped region to target resolution.
      // IMPORTANT: libx264 requires even dimensions.
      int outW = (_intersectW % 2 == 0) ? _intersectW : _intersectW - 1;
      int outH = (_intersectH % 2 == 0) ? _intersectH : _intersectH - 1;
      if (outW <= 0) outW = 2; // Safety
      if (outH <= 0) outH = 2;

      filters.add('scale=$outW:$outH:flags=lanczos');
      
      // C. Removed minterpolate for stability. It is very heavy and crash prone on some backends.
      // filters.add("minterpolate='mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1'");

      String filterString = filters.join(',');
      
      // Use system ffmpeg
      const String ffmpegPath = 'ffmpeg';

       List<String> args = [
         '-i', sourcePath,
        '-vf', filterString,
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        '-preset', 'medium', // Better compression for final export
        '-y', outputPath
      ];

      debugPrint("FFmpeg Command: $ffmpegPath ${args.join(' ')}");

      final result = await Process.run(ffmpegPath, args);
      
      if (mounted) {
        Navigator.pop(context); // Hide loader
        if (result.exitCode == 0) {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Video Exported Successfully!")));
             
             if (outputPath != null) {
                context.read<ShowState>().updateMedia(outputPath);
             }
        } else {
             // Show Detailed Error Dialog
             showDialog(
               context: context,
               builder: (c) => AlertDialog(
                 title: const Text("Export Failed"),
                 content: SingleChildScrollView(
                   child: Text("FFmpeg Error (Exit ${result.exitCode}):\n\n${result.stderr}"),
                 ),
                 actions: [
                   TextButton(onPressed: () => Navigator.pop(c), child: const Text("OK")),
                 ],
               ),
             );
        }
      }
    } catch (e) {
      debugPrint("Export Error: $e");
      if(mounted) {
         Navigator.pop(context);
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  void _fitToMatrix() {
    final show = context.read<ShowState>().currentShow;
    if (show == null || show.fixtures.isEmpty) return;

    final width = _bgPlayer.state.width;
    final height = _bgPlayer.state.height;
    if (width == null || height == null) return;
    
    // 1. Calculate Matrix Bounds in "Pixel" space (10.0 scale)
    double minMx = double.infinity, maxMx = double.negativeInfinity;
    double minMy = double.infinity, maxMy = double.negativeInfinity;
    const double gridSize = 10.0;
    
    for (var f in show.fixtures) {
       for (var p in f.pixels) {
           double px = p.x * gridSize;
           double py = p.y * gridSize;
           if (px < minMx) minMx = px;
           if (px > maxMx) maxMx = px;
           if (py < minMy) minMy = py;
           if (py > maxMy) maxMy = py;
       }
    }
    maxMx += gridSize; // full width
    maxMy += gridSize; // full height
    
    double matW = maxMx - minMx;
    double matH = maxMy - minMy;
    
    // 2. Calculate Required Scale
    // Video Size Visual = VideoPx * Scale
    
    double targetScaleX = 1.0;
    double targetScaleY = 1.0;
    
    if (!_lockAspectRatio) {
       // STRETCH: Visual Size == Matrix Size
       targetScaleX = matW / width;
       targetScaleY = matH / height;
    } else {
       // CONTAIN: Fit inside Matrix
       // Min(MatrixW / VideoW, MatrixH / VideoH)
       double rX = matW / width;
       double rY = matH / height;
       double scale = (rX < rY) ? rX : rY;
       targetScaleX = scale;
       targetScaleY = scale;
    }
    
    // 3. Center Alignment
    // Reset translation to 0,0 aligns video center to matrix center (in our specific stack layout)
    
    setState(() {
       // _isEditingCrop = false;
       context.read<ShowState>().updateLayer(
         isForeground: _isForegroundSelected, 
         transform: MediaTransform(
            scaleX: targetScaleX,
            scaleY: targetScaleY,
            translateX: 0,
            translateY: 0,
            rotation: 0,
            crop: null,
         )
       );
    });
    
    debugPrint("Auto-Fit Applied");
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Auto-Fit Applied"), duration: Duration(milliseconds: 500)));
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
        final activeLayer = _isForegroundSelected ? show.foregroundLayer : show.backgroundLayer;
        final activeParams = activeLayer.effectParams;

        return Row(
          children: [
            // Main Editor Area
            Expanded(
              child: Container(
                color: Colors.black87,
                child: RepaintBoundary(
                  key: _previewKey,
                  child: ClipRect(
                    child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // UNIFIED LAYOUT
                      LayoutBuilder(
                        builder: (context, constraints) {
                           // 1. Calculate Matrix Bounds (Logical 10.0 scale)
                           double minX = double.infinity, maxX = double.negativeInfinity;
                           double minY = double.infinity, maxY = double.negativeInfinity;
                           const double gridSize = 10.0;
                           bool hasFixtures = show.fixtures.isNotEmpty;
                           
                           if (hasFixtures) {
                             for (var f in show.fixtures) {
                               for (var p in f.pixels) {
                                   double px = p.x * gridSize;
                                   double py = p.y * gridSize;
                                   if (px < minX) minX = px;
                                   if (px > maxX) maxX = px;
                                   if (py < minY) minY = py;
                                   if (py > maxY) maxY = py;
                               }
                             }
                             // Add grid block size
                             maxX += gridSize; 
                             maxY += gridSize;
                           } else {
                             // Default Space if no matrix
                             minX = 0; maxX = 1000;
                             minY = 0; maxY = 1000;
                           }
                           
                           double matW = maxX - minX;
                           double matH = maxY - minY;
                           
                           if (matW <= 0) matW = 1000;
                           if (matH <= 0) matH = 1000;

                           return FittedBox(
                             fit: BoxFit.contain,
                             child: Container(
                               width: matW,
                               height: matH,
                               color: Colors.transparent, // "World" Canvas
                               child: Stack(
                                 clipBehavior: Clip.none,
                                 alignment: Alignment.center,
                                 children: [
                                    // LAYER 1: Matrix (Localized)
                                    // Translate so (minX, minY) is at (0,0) of this container
                                    if (hasFixtures)
                                      Positioned(
                                        left: -minX, 
                                        top: -minY,
                                        child: CustomPaint(
                                          painter: PixelGridPainter(
                                             fixtures: show.fixtures, 
                                             drawLabels: false,
                                             gridSize: gridSize
                                          ),
                                        ),
                                      ),
                                    
                                   // LAYER 2: Video/Effects Composition
                                    Center(
                                      child: OverflowBox(
                                          minWidth: (_bgPlayer.state.width ?? 1920).toDouble(),
                                          maxWidth: (_bgPlayer.state.width ?? 1920).toDouble(),
                                          minHeight: (_bgPlayer.state.height ?? 1080).toDouble(),
                                          maxHeight: (_bgPlayer.state.height ?? 1080).toDouble(),
                                          alignment: Alignment.center,
                                          child: Stack(
                                            children: [
                                              // 1. Background Layer (Bottom)
                                              IgnorePointer(
                                                ignoring: _isForegroundSelected, // Ignore if FG is selected (Pass-through NOT ensuring BG capture, but BG is behind)
                                                // Actually, if FG is on top and ignoring, click goes to BG.
                                                // If FG is on top and NOT ignoring, click goes to FG.
                                                child: TransformGizmo(
                                                  transform: show.backgroundLayer.transform ?? MediaTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0),
                                                  isCropMode: true,
                                                  editMode: EditMode.zoom,
                                                  lockAspect: _lockAspectRatio,
                                                  onDoubleTap: _fitToMatrix,
                                                  onUpdate: (newTransform) {
                                                    // Only update if BG is selected (redundant check but safe)
                                                    if (!_isForegroundSelected) {
                                                      showState.updateLayer(isForeground: false, transform: newTransform);
                                                      _calculateIntersection();
                                                    }
                                                  },
                                                  child: SizedBox(
                                                    width: (_bgPlayer.state.width ?? 1920).toDouble(),
                                                    height: (_bgPlayer.state.height ?? 1080).toDouble(),
                                                    child: LayerRenderer(
                                                      layer: show.backgroundLayer,
                                                      controller: _bgController
                                                    ),
                                                  ),
                                                ),
                                              ),

                                              // 2. Foreground Layer (Top)
                                              IgnorePointer(
                                                ignoring: !_isForegroundSelected, // Ignore if BG is selected
                                                child: TransformGizmo(
                                                  transform: show.foregroundLayer.transform ?? MediaTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0),
                                                  isCropMode: true,
                                                  editMode: EditMode.zoom,
                                                  lockAspect: _lockAspectRatio,
                                                  onDoubleTap: _fitToMatrix,
                                                  onUpdate: (newTransform) {
                                                    if (_isForegroundSelected) {
                                                      showState.updateLayer(isForeground: true, transform: newTransform);
                                                      _calculateIntersection();
                                                    }
                                                  },
                                                  child: SizedBox(
                                                    width: (_bgPlayer.state.width ?? 1920).toDouble(), // Use BG dimensions for now as reference? Or FG player dimensions?
                                                    // Effect might default to 1920x1080.
                                                    // If FG is video, prefer FG dimensions.
                                                    height: (_bgPlayer.state.height ?? 1080).toDouble(),
                                                    child: LayerRenderer(
                                                      layer: show.foregroundLayer,
                                                      controller: _fgController
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                      ),
                                    ),
                                 ],
                               ),
                             ),
                           );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),


            // Glass Sidebar
            GlassContainer(
              padding: const EdgeInsets.all(20.0),
              tint: Colors.black, // Dark panel
              opacity: 0.95,       // Almost opaque for visibility
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
              border: const Border(left: BorderSide(color: Colors.white24)), // Brighter border
              child: SizedBox(
                width: 320,
                child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     // 1. Header
                     Text("PROJECT LAYERS", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                     const SizedBox(height: 12),
                     
                     // Layer Toggle
                     Container(
                        decoration: BoxDecoration(
                           color: Colors.white24, // Brighter track
                           borderRadius: BorderRadius.circular(8),
                           border: Border.all(color: Colors.white12)
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Row(
                           children: [
                              Expanded(
                                 child: GestureDetector(
                                    onTap: () => setState(() => _isForegroundSelected = false),
                                    child: AnimatedContainer(
                                       duration: const Duration(milliseconds: 200),
                                       padding: const EdgeInsets.symmetric(vertical: 10), // Taller hit area
                                       decoration: BoxDecoration(
                                          color: !_isForegroundSelected ? Colors.blue : Colors.transparent, // Opaque Blue
                                          borderRadius: BorderRadius.circular(6),
                                          boxShadow: !_isForegroundSelected ? [
                                             BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 2))
                                          ] : null
                                       ),
                                       child: Center(child: Text("BACKGROUND", style: TextStyle(
                                          color: !_isForegroundSelected ? Colors.white : Colors.white70, 
                                          fontWeight: FontWeight.bold, 
                                          fontSize: 12,
                                          letterSpacing: 1.0
                                       ))),
                                    ),
                                 ),
                              ),
                              Expanded(
                                 child: GestureDetector(
                                    onTap: () => setState(() => _isForegroundSelected = true),
                                    child: AnimatedContainer(
                                       duration: const Duration(milliseconds: 200),
                                       padding: const EdgeInsets.symmetric(vertical: 10),
                                       decoration: BoxDecoration(
                                          color: _isForegroundSelected ? Colors.purpleAccent : Colors.transparent, // Different color for FG for distinction? Or just Blue? Let's use Blue for consistency or Purple for FG differentiation. Let's stick to Blue for now for "Active" state consistency, or maybe an accent color.
                                          // Actually, let's use the same Active Color (Blue) to imply "Selected".
                                          // OR: Background = Blue, Foreground = Purple? 
                                          // Let's use Blue for both to reduce cognitive load.
                                          color: _isForegroundSelected ? Colors.blue : Colors.transparent, 
                                          borderRadius: BorderRadius.circular(6),
                                          boxShadow: _isForegroundSelected ? [
                                             BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 2))
                                          ] : null
                                       ),
                                       child: Center(child: Text("FOREGROUND", style: TextStyle(
                                          color: _isForegroundSelected ? Colors.white : Colors.white70, 
                                          fontWeight: FontWeight.bold, 
                                          fontSize: 12,
                                          letterSpacing: 1.0
                                       ))),
                                    ),
                                 ),
                              ),
                           ],
                        ),
                     ),
                     const SizedBox(height: 24),
                     
                     Text("${_isForegroundSelected ? "FOREGROUND" : "BACKGROUND"} SETTINGS", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                     const SizedBox(height: 4),
                     
                     // Opacity Slider
                     Text("Opacity: ${(_isForegroundSelected ? show.foregroundLayer.opacity : show.backgroundLayer.opacity).toStringAsFixed(2)}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                     Slider(
                        value: _isForegroundSelected ? show.foregroundLayer.opacity : show.backgroundLayer.opacity,
                        min: 0.0,
                        max: 1.0,
                        activeColor: const Color(0xFF90CAF9),
                        inactiveColor: Colors.white12,
                        onChanged: (v) {
                           context.read<ShowState>().updateLayer(
                              isForeground: _isForegroundSelected, 
                              opacity: v
                           );
                        },
                     ),
                     const SizedBox(height: 12),
                     
                     // Active Layer Info
                     Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
                        child: Row(
                           children: [
                              Icon(
                                 (_isForegroundSelected ? show.foregroundLayer.type : show.backgroundLayer.type) == LayerType.video ? Icons.movie : Icons.auto_fix_high,
                                 color: Colors.white70, size: 20
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                   (_isForegroundSelected ? show.foregroundLayer.type : show.backgroundLayer.type) == LayerType.none 
                                      ? "No Content" 
                                      : ((_isForegroundSelected ? show.foregroundLayer.path : show.backgroundLayer.path) ?? "Effect"),
                                   overflow: TextOverflow.ellipsis,
                                   style: const TextStyle(color: Colors.white, fontSize: 12)
                                ),
                              ),
                              IconButton(
                                 icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                                 onPressed: () {
                                    context.read<ShowState>().updateLayer(
                                       isForeground: _isForegroundSelected,
                                       type: LayerType.none,
                                       path: null,
                                       effect: null
                                    );
                                 },
                              )
                           ],
                        ),
                     ),
                     
                     const SizedBox(height: 24),
  
                     // 2. Primary Actions (Grid)
                     GridView.count(
                       crossAxisCount: 2,
                       crossAxisSpacing: 10,
                       mainAxisSpacing: 10,
                       shrinkWrap: true, // Vital for nesting in Column
                       physics: const NeverScrollableScrollPhysics(),
                       childAspectRatio: 1.3,
                       children: [
                          _buildModernButton(
                            icon: Icons.upload_file, 
                            label: "Load Video", 
                            color: const Color(0xFF90CAF9), // Pastel Blue
                            onTap: () => _pickVideo(context)
                          ),
                          // Only save show (bundle), not individual video export for now in this button?
                          // Keeping it as "Save Video" (Export) but warning it only exports bg.
                          _buildModernButton(
                            icon: Icons.save, 
                            label: "Export Crop", 
                            color: const Color(0xFFA5D6A7), // Pastel Green
                            isEnabled: show.backgroundLayer.path != null,
                            onTap: () => _exportVideo()
                          ),
                          // Full width transfer button? Or just another tile.
  
                       ],
                     ),
                     const SizedBox(height: 32),
  
                     // 2.5 Playback Controls
                     if (show.mediaFile.isNotEmpty) ...[
  
                        GlassContainer(
                           padding: EdgeInsets.zero,
                           borderRadius: BorderRadius.circular(50),
                           child: Row(
                             mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                             children: [
                               IconButton(
                                 onPressed: () => player.playOrPause(),
                                 icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                                 color: Colors.white,
                                 tooltip: _isPlaying ? "Pause" : "Play",
                               ),
                               IconButton(
                                 onPressed: () async {
                                   await _bgPlayer.seek(Duration.zero);
                                   await _fgPlayer.seek(Duration.zero);
                                   await _bgPlayer.pause();
                                   await _fgPlayer.pause();
                                 },
                                 icon: const Icon(Icons.stop),
                                 color: Colors.redAccent,
                                 tooltip: "Stop",
                               ),
                             ],
                           ),
                        )
                      ],
                        const SizedBox(height: 24),
  
  
                     // 3. Edit Modes (Simplifed)
                     if (show.mediaFile.isNotEmpty) ...[
                        // Intersection Info
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
                                Text("MATRIX INTERSECTION", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                if (_currentIntersection != null) ...[
                                   _buildInfoRow("X Start", "$_displayX"),
                                   _buildInfoRow("Width", "${_intersectW} px"),
                                   _buildInfoRow("Y Start", "$_displayY"),
                                   _buildInfoRow("Height", "${_intersectH} px"),
                                ] else 
                                   Text("No Intersection / No Matrix", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                             ],
                          ),
                        ),
                        const SizedBox(height: 12),
  
                        Row(
                           children: [
                              Text("Lock Aspect", style: const TextStyle(color: Colors.white70)),
                              const Spacer(),
                              Switch(
                                value: _lockAspectRatio, 
                                activeThumbColor:  const Color(0xFF90CAF9),
                                onChanged: (v) => setState(() => _lockAspectRatio = v)
                              ),
                           ],
                        ),
                        const Divider(color: Colors.white12, height: 32),
                     ],
  
                     // 4. Effects or Effect Controls
                     if (_selectedEffect != null) ...[
                        Text("EFFECT SETTINGS: ${_selectedEffect!.name.toUpperCase()}", style: const TextStyle(color: Color(0xFFA5D6A7), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                         
                        // Removed Expanded
                        Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                                 ...activeParams.keys.map((key) {
                                    // Guard: ensure key exists (redundant if iterating keys, but safe)
                                    if (!activeParams.containsKey(key)) return const SizedBox.shrink();

                                    final def = EffectService.effects.firstWhere((e) => e.type == _selectedEffect);
                                    double min = def.minParams[key] ?? 0.0;
                                    double max = def.maxParams[key] ?? 1.0;
                                    
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("$key: ${(activeParams[key] ?? min).toStringAsFixed(2)}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                        Slider(
                                          value: activeParams[key] ?? min,
                                          min: min,
                                          max: max,
                                          activeColor: const Color(0xFF90CAF9),
                                          inactiveColor: Colors.white12,
                                          onChanged: (v) {
                                             final newParams = Map<String, double>.from(activeParams);
                                             newParams[key] = v;
                                             context.read<ShowState>().updateLayer(
                                                isForeground: _isForegroundSelected, 
                                                params: newParams
                                             );
                                          },
                                        ),
                                      ],
                                    );
                               }),
                               const SizedBox(height: 20),
                               _buildModernButton(
                                 icon: Icons.check, 
                                 label: "Apply & Close", 
                                 color: const Color(0xFF90CAF9),
                                 onTap: () => setState(() => _selectedEffect = null), // Or just deselect to view
                               ),
                             ],
                           ),
                     ] else ...[
                         Text("EFFECTS LIBRARY", style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                         const SizedBox(height: 12),
                         // Removed Expanded and added shrinkWrap
                         ListView(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: EffectType.values.map((e) {
                               return Container(
                                 margin: const EdgeInsets.only(bottom: 8),
                                 decoration: BoxDecoration(
                                   color: Colors.white.withValues(alpha: 0.05),
                                   borderRadius: BorderRadius.circular(8),
                                 ),
                                 child: ListTile(
                                   leading: Icon(Icons.auto_fix_high, color: Colors.white70),
                                   title: Text(e.name.toUpperCase(), style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                                  onTap: () {
                                    // Apply Effect to Active Layer
                                    context.read<ShowState>().updateLayer(
                                       isForeground: _isForegroundSelected,
                                       type: LayerType.effect,
                                       effect: e,
                                       opacity: 1.0, 
                                       params: EffectService.effects.firstWhere((eff) => eff.type == e).defaultParams
                                    );
                                    
                                    // Also set local state for editing?
                                    // Actually, we should probably read from ShowState
                                    // But for now keeping local override logic or removing it? 
                                    // Let's rely on ShowState.
                                    
                                    setState(() {
                                      _selectedEffect = e;
                                      // _loadEffectDefaults(e); // Handled by updateLayer defaultParams
                                    });
                                  },
                                ),
                              );
                           }).toList(),
                         ),

                   ],

                  ],

                ),
              ),
            ),
            ),
          ],
        );
      },
    );
  }



  // MARK: - Intersection Logic
  void _calculateIntersection() {
    final show = context.read<ShowState>().currentShow;
    if (show == null) return;
    
    final activeLayer = _isForegroundSelected ? show.foregroundLayer : show.backgroundLayer;
    final transform = activeLayer.transform ?? MediaTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0);

    final width = _bgPlayer.state.width;
    final height = _bgPlayer.state.height;
    
    if (show.fixtures.isEmpty || width == null || height == null) {
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

    const double gridSize = 10.0;
    
    // 1. Matrix Bounds (Logic Space)
    double minMx = double.infinity, maxMx = double.negativeInfinity;
    double minMy = double.infinity, maxMy = double.negativeInfinity;
    
    for (var f in show.fixtures) {
       for (var p in f.pixels) {
          double px = p.x * gridSize;
          double py = p.y * gridSize;
          if (px < minMx) minMx = px;
          if (px > maxMx) maxMx = px;
          if (py < minMy) minMy = py;
          if (py > maxMy) maxMy = py;
       }
    }
    maxMx += gridSize; 
    maxMy += gridSize;
    
    double matW = maxMx - minMx;
    double matH = maxMy - minMy;
    
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
       int w = (intersect.width / gridSize).round();
       int h = (intersect.height / gridSize).round();
       
       // Calculate Display Coordinates (Bottom-Left Origin)
       // X Start: Distance from Left Edge
       double matLeft = matrixRect.left;
       double xDist = intersect.left - matLeft;
       int dX = (xDist / gridSize).round();

       // Y Start: Distance from Bottom Edge (Flutter Y grows down)
       // Matrix Bottom (Max Y) - Intersect Bottom (Max Y of intersection)
       double matBottom = matrixRect.bottom;
       double yDist = matBottom - intersect.bottom; 
       int dY = (yDist / gridSize).round();

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
     double minMy = double.infinity, maxMy = double.negativeInfinity;
     
     for (var f in show.fixtures) {
        for (var p in f.pixels) {
           double px = p.x * gridSize;
           double py = p.y * gridSize;
           if (px < minMx) minMx = px;
           if (px > maxMx) maxMx = px;
           if (py < minMy) minMy = py;
           if (py > maxMy) maxMy = py;
        }
     }
     maxMx += gridSize; 
     maxMy += gridSize;
     
     double matW = maxMx - minMx;
     double matH = maxMy - minMy;
     
     // 2. Video Bounds (Logic Space) relative to Matrix Center
     // Matrix is centered at (0,0) visually.
     // Video is transformed relative to (0,0).
     
     final t = show.backgroundLayer.transform ?? MediaTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0);
     
     // Video Original Size
     final vidW = width.toDouble();
     final vidH = height.toDouble();
     
     // Scaled Size
     final scaledW = vidW * t.scaleX;
     final scaledH = vidH * t.scaleY;
     
     // TopLeft of Video relative to Center (0,0)
     // Center is at t.translateX, t.translateY
     final vidLeft = t.translateX - (scaledW / 2);
     final vidTop = t.translateY - (scaledH / 2);
     
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
        int w = (intersect.width / gridSize).round();
        int h = (intersect.height / gridSize).round();
        
        // Calculate Display Coordinates (Bottom-Left Origin)
        // X Start: Distance from Left Edge
        double matLeft = matrixRect.left;
        double xDist = intersect.left - matLeft;
        int dX = (xDist / gridSize).round();

        // Y Start: Distance from Bottom Edge (Flutter Y grows down)
        // Matrix Bottom (Max Y) - Intersect Bottom (Max Y of intersection)
        double matBottom = matrixRect.bottom;
        double yDist = matBottom - intersect.bottom; 
        int dY = (yDist / gridSize).round();

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
          isForeground: _isForegroundSelected, 
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
