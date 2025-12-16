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
import 'package:provider/provider.dart';

import '../../models/show_manifest.dart';
import '../../state/show_state.dart';
import '../../services/effect_service.dart';
import '../widgets/pixel_grid_painter.dart';
import '../widgets/transform_gizmo.dart';
import '../widgets/effect_renderer.dart';
import '../widgets/transfer_dialog.dart';

// Enum removed, using from transform_gizmo.dart

class ShowsTab extends StatefulWidget {
  const ShowsTab({super.key});

  @override
  State<ShowsTab> createState() => _ShowsTabState();
}

class _ShowsTabState extends State<ShowsTab> {
  late final Player player;
  late final VideoController controller;
  
  String? _loadedFilePath;
  
  // REMOVED: bool _isEditingCrop = false;
  // REMOVED: MediaTransform? _tempTransform;
  
  // NEW: Intersection State for UI
  Rect? _currentIntersection;
  int _intersectW = 0;
  int _intersectH = 0;
  int _displayX = 0;
  int _displayY = 0;

  // Temp size overrides to prevent flash when switching media
  int? _overrideWidth;
  int? _overrideHeight;

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
  Map<String, double> _effectParams = {};
  
  final GlobalKey _previewKey = GlobalKey(); // For Snapshot
  
  // Debounce for fit
  Timer? _fitDebounce;

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    
    _playingSubscription = player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          _isPlaying = playing;
        });
      }
    });

    // Auto-Fit Listener & Override Clear
    _widthSubscription = player.stream.width.listen((w) {
       if (w != null && w > 0) {
          if (mounted) {
             setState(() {
                if (_overrideWidth != null || _overrideHeight != null) {
                   _overrideWidth = null; 
                   _overrideHeight = null; 
                }
             });
          }
       }
       _checkAutoFit();
       // FORCE Intersection Calculation on Load (if not auto-fitting)
       if (!_pendingAutoFit && w != null && w > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
             if (mounted) _calculateIntersection();
          });
       }
    });
    _heightSubscription = player.stream.height.listen((h) => _checkAutoFit());
  }
  
  void _checkAutoFit() {
     if (!_pendingAutoFit) return;
     
     final w = player.state.width;
     final h = player.state.height;
     
     if (w != null && h != null && w > 0 && h > 0) {
        _autoFitVideoToMatrix(w, h);
        _pendingAutoFit = false;
     }
  }

  void _autoFitVideoToMatrix(int videoW, int videoH) {
     final show = context.read<ShowState>().currentShow;
     if (show == null || show.fixtures.isEmpty) return;

     // 1. Calculate Matrix Bounds (pixels)
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
     maxMx += gridSize; 
     maxMy += gridSize;
     
     if (minMx == double.infinity) return;

     double boundsW = maxMx - minMx;
     double boundsH = maxMy - minMy;

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
        
        _calculateIntersection(); // Force UI update
        
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
    player.dispose();
    super.dispose();
  }

  Future<void> _pickVideo(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      dialogTitle: 'Select Video File',
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      if (context.mounted) {
        // RESET Logic:
        setState(() {
           // _isEditingCrop = false;
           // _tempTransform = null;
           _selectedEffect = null; // Clear effect
           _pendingAutoFit = true; // Trigger auto-fit on next load
        });

        // 2. Update Media in ShowState (which resets transform to defaults)
        context.read<ShowState>().updateMedia(path);
      }
    }
  }

  void _syncPlayer(String? mediaFile) {
    // If effect mode is active, don't sync player to user interactions yet or pause it logic
    if (_selectedEffect != null) return;

    if (mediaFile == null || mediaFile.isEmpty) {
      if (_loadedFilePath != null || _overrideWidth != null) {
         player.stop();
         _loadedFilePath = null;
         
         // Clear overrides on New Show / Unload
         WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
               setState(() {
                  _overrideWidth = null; 
                  _overrideHeight = null;
                  _displayX = 0;
                  _displayY = 0;
                  _intersectW = 0;
                  _intersectH = 0;
                  _currentIntersection = null;
               });
            }
         });
      }
      return;
    }

    if (_loadedFilePath != mediaFile) {
      player.open(Media(mediaFile), play: true);
      player.setPlaylistMode(PlaylistMode.loop);
      _loadedFilePath = mediaFile;
      
      // Safety check: ensure local state is clean when a new video plays
       WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
             setState(() {
               // _isEditingCrop = false;
               // _tempTransform = null;
             });
          }
       });
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
        final filter = EffectService.getFFmpegFilter(_selectedEffect!, _effectParams);
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

  Future<void> _showTransferDialog() async {
     // 1. Capture Thumbnail
     final thumb = await _captureThumbnail();
     if (thumb == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to capture thumbnail")));
       return;
     }

     if (!mounted) return;
     
     // 2. Show Dialog
     showDialog(
       context: context,
       barrierDismissible: false,
       builder: (c) => TransferDialog(thumbnail: thumb),
     );
  }

  Future<void> _exportVideo() async {
    final show = context.read<ShowState>().currentShow;
    if (show == null || show.mediaFile.isEmpty) return;

    // Must have intersection to export
    if (_currentIntersection == null || _intersectW <= 0 || _intersectH <= 0) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No Intersection with Matrix! Move video over matrix to export.")));
       return;
    }

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
      final baseT = show.mediaTransform ?? MediaTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0);
      final t = baseT;
      
      final width = player.state.width;
      final height = player.state.height;

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
        '-i', show.mediaFile,
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

    final width = player.state.width;
    final height = player.state.height;
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
       context.read<ShowState>().updateTransform(MediaTransform(
          scaleX: targetScaleX,
          scaleY: targetScaleY,
          translateX: 0,
          translateY: 0,
          rotation: 0,
          crop: null, // Reset crop
       ));
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

        _syncPlayer(show.mediaFile);

        final baseTransform = show.mediaTransform ??
            MediaTransform(
                scaleX: 1.0,
                scaleY: 1.0,
                translateX: 0.0,
                translateY: 0.0,
                rotation: 0.0);

        final transform = baseTransform;
        
        // Debug Log
        // debugPrint("Build: Media=${show.mediaFile}, T=${transform.scaleX}x${transform.scaleY}, PlayerW=${player.state.width}");

        return Scaffold(
           backgroundColor: Colors.transparent,
           body: Row(
             crossAxisAlignment: CrossAxisAlignment.stretch,
             children: [
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
                           debugPrint("World Bounds: ${matW}x${matH}");

                           // REMOVED FittedBox for Debugging
                           return Center(
                             child: Transform.scale(
                               scale: 0.5,
                               child: Container(
                               width: matW,
                               height: matH,
                               color: Colors.transparent, // "World" Canvas
                               child: Listener(
                                 onPointerDown: (_) => debugPrint("Layer 0: World Stack Hit"),
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
                                    
                                    // LAYER 2: Video (Gizmo)
                                    // We need to place the Video Logic Center at the Canvas Logic Center.
                                    // Canvas Center = (matW/2, matH/2).
                                    // Gizmo is centered by 'Alignment.center' of Stack?
                                    // Stack size is matW, matH. 
                                    // Alignment.center puts child center at (matW/2, matH/2).
                                    // So this aligns perfectly!
                                    
                                    if (show.mediaFile.isNotEmpty || _selectedEffect != null)
                                      Center(
                                        child: OverflowBox(
                                           minWidth: ((_overrideWidth ?? player.state.width ?? 1920) * transform.scaleX.abs()).toDouble(),
                                           maxWidth: ((_overrideWidth ?? player.state.width ?? 1920) * transform.scaleX.abs()).toDouble(),
                                           minHeight: ((_overrideHeight ?? player.state.height ?? 1080) * transform.scaleY.abs()).toDouble(),
                                           maxHeight: ((_overrideHeight ?? player.state.height ?? 1080) * transform.scaleY.abs()).toDouble(),
                                           alignment: Alignment.center,
                                           child: Listener(
                                            onPointerDown: (_) => debugPrint("Layer 1: Gizmo Wrapper Hit"),
                                            child: TransformGizmo(
                                              transform: transform,
                                              isCropMode: true, // Show handles
                                              editMode: EditMode.zoom, // ALWAYS ZOOM/PAN
                                              lockAspect: _lockAspectRatio,
                                              onDoubleTap: _fitToMatrix,
                                              onUpdate: (newTransform) {
                                                   showState.updateTransform(newTransform);
                                                   _calculateIntersection(); // Update UI info
                                              },
                                              child: Container(
                                                width: (player.state.width ?? 1920).toDouble(),
                                                height: (player.state.height ?? 1080).toDouble(),
                                                child: (_selectedEffect != null) 
                                                  ? AspectRatio(
                                                      aspectRatio: 16 / 9,
                                                      child: EffectRenderer(
                                                          type: _selectedEffect, 
                                                          params: _effectParams,
                                                          isPlaying: _isPlaying
                                                      )
                                                    )
                                                  : Video(controller: controller, fit: BoxFit.fill, controls: NoVideoControls),
                                              ),
                                            ),
                                        ),
                                      )
                                     else
                                      const Center(
                                        child: Text(
                                          "No video loaded.\nUse 'Load Video' on the right panel.",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.white54, fontSize: 40), // Large text for large world
                                        ),
                                      ),
                                 ],
                               ),
                             ),
                             ), // Close Transform
                           ); // Close Center
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),


            // NEW: Modern Sidebar
            Container(
              width: 320,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E), // Dark charcoal
                border: const Border(left: BorderSide(color: Colors.white12)),
                boxShadow: [
                   BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(-2, 0))
                ]
              ),
              padding: const EdgeInsets.all(20.0),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 150), // Prevent bottom overflow
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     // 1. Header
                     Text("COMPOSER", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                     const SizedBox(height: 4),
                     
                     // Project Name & Status
                     Row(
                       children: [
                         Expanded(child: Text(show.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                         IconButton(
                           icon: const Icon(Icons.edit, size: 16, color: Colors.white54),
                           onPressed: () async {
                              final nameController = TextEditingController(text: show.name);
                              final newName = await showDialog<String>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text("Rename Show"),
                                  content: TextField(
                                    controller: nameController,
                                    decoration: const InputDecoration(labelText: "Show Name"),
                                    autofocus: true,
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                                    ElevatedButton(onPressed: () => Navigator.pop(context, nameController.text), child: const Text("Save")),
                                  ],
                                ),
                              );
                              if (newName != null && newName.isNotEmpty) {
                                showState.updateName(newName);
                              }
                           },
                         )
                       ],
                     ),
                     Text(showState.isModified ? "Unsaved Changes" : "Saved", style: TextStyle(color: showState.isModified ? Colors.orangeAccent : Colors.grey, fontSize: 10)),
                     const SizedBox(height: 20),
  
                     // 2. Main Actions (Grid)
                     GridView.count(
                       crossAxisCount: 2,
                       crossAxisSpacing: 10,
                       mainAxisSpacing: 10,
                       shrinkWrap: true, 
                       physics: const NeverScrollableScrollPhysics(),
                       childAspectRatio: 1.5, // Slightly wider buttons
                       children: [
                          _buildModernButton(
                            icon: Icons.add, 
                            label: "New Show", 
                            color: Colors.grey, 
                            onTap: () async {
                               if (showState.isModified) {
                                  final confirm = await showDialog<bool>(
                                     context: context,
                                     builder: (c) => AlertDialog(
                                        title: const Text("Discard Changes?"),
                                        content: const Text("You have unsaved changes. Create new show anyway?"),
                                        actions: [
                                           TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Cancel")),
                                           ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text("Discard & New"))
                                        ]
                                     )
                                  );
                                  if (confirm != true) return;
                               }
                               showState.newShow();
                            }
                          ),
                          _buildModernButton(
                            icon: Icons.folder, 
                            label: "Load Show", 
                            color: Colors.grey, 
                            onTap: () async {
                               if (showState.isModified) {
                                   // Warning omitted for brevity, logic same as above
                               }
                               showState.loadShow();
                            }
                          ),
                          _buildModernButton(
                            icon: Icons.save, 
                            label: "Save Show", 
                            color: const Color(0xFF90CAF9), 
                            isEnabled: show.mediaFile.isNotEmpty, // "Otherwise disabled"
                            onTap: () => _saveShowAndFlatten()
                          ),
                          _buildModernButton(
                            icon: Icons.video_library, 
                            label: "Load Video", 
                            color: Colors.blueGrey, 
                            onTap: () => _pickVideo(context)
                          ),
                       ],
                     ),
                     
                     const SizedBox(height: 10),
                     // Export Action (Separate)
                     SizedBox(
                       width: double.infinity,
                       child: _buildModernButton(
                             icon: Icons.output, 
                             label: "Export to Matrix (MP4)", 
                             color: const Color(0xFFA5D6A7), 
                             isEnabled: show.mediaFile.isNotEmpty || _selectedEffect != null,
                             onTap: () => (_selectedEffect != null) ? _exportEffect() : _exportVideo()
                       ),
                     ),
                     const SizedBox(height: 24),
                     const SizedBox(height: 32),
  
                     // 2.5 Playback Controls
                     if (show.mediaFile.isNotEmpty) ...[
  
                        Row(
                          children: [
                             Expanded(
                               child: Container(
                                 decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
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
                                         await player.seek(Duration.zero);
                                         await player.pause();
                                       },
                                       icon: const Icon(Icons.stop),
                                       color: Colors.redAccent,
                                       tooltip: "Stop",
                                     ),
                                   ],
                                 ),
                               ),
                             )
                          ],
                        ),
                        const SizedBox(height: 24),
                     ],
  
  
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
                                Text("MATRIX INTERSECTION", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
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
                                activeColor:  const Color(0xFF90CAF9),
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
                                ..._effectParams.keys.map((key) {
                                    final def = EffectService.effects.firstWhere((e) => e.type == _selectedEffect);
                                    double min = def.minParams[key] ?? 0.0;
                                    double max = def.maxParams[key] ?? 1.0;
                                    
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("$key: ${_effectParams[key]!.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                        Slider(
                                          value: _effectParams[key]!,
                                          min: min,
                                          max: max,
                                          activeColor: const Color(0xFF90CAF9),
                                          inactiveColor: Colors.white12,
                                          onChanged: (v) => setState(() => _effectParams[key] = v),
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
                         Text("EFFECTS LIBRARY", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                         const SizedBox(height: 12),
                         // Removed Expanded and added shrinkWrap
                         ListView(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: EffectType.values.map((e) {
                               return Container(
                                 margin: const EdgeInsets.only(bottom: 8),
                                 decoration: BoxDecoration(
                                   color: Colors.white.withOpacity(0.05),
                                   borderRadius: BorderRadius.circular(8),
                                 ),
                                 child: ListTile(
                                   leading: Icon(Icons.auto_fix_high, color: Colors.white70),
                                   title: Text(e.name.toUpperCase(), style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                                  onTap: () {
                                    setState(() {
                                      _selectedEffect = e;
                                      _loadEffectDefaults(e);
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
          ],
        ));
      },
    );
  }



  // MARK: - Intersection Logic
  void _calculateIntersection() {
     final show = context.read<ShowState>().currentShow;
     final width = player.state.width;
     final height = player.state.height;
     
     if (show == null || show.fixtures.isEmpty || width == null || height == null) {
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
     
     final t = show.mediaTransform ?? MediaTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0);
     
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
       setState(() {
          _effectParams = Map.from(def.defaultParams);
          _isPlaying = true;
          // if (player.state.playing) player.pause(); // Optional: pause video to focus on effect?
       });
     } catch (e) {
       debugPrint("Error loading defaults for $type: $e");
     }
  }

  Widget _buildModernButton({required IconData icon, required String label, required Color color, required VoidCallback? onTap, bool isEnabled = true}) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEnabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              gradient: isEnabled ? LinearGradient(colors: [color.withOpacity(0.8), color.withOpacity(0.5)], begin: Alignment.topLeft, end: Alignment.bottomRight) 
                                :  const LinearGradient(colors: [Colors.white10, Colors.white10]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isEnabled ? color.withOpacity(0.6) : Colors.white10),
              boxShadow: isEnabled ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))] : [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: isEnabled ? Colors.white : Colors.white38, size: 28),
                const SizedBox(height: 8),
                Text(label, style: TextStyle(color: isEnabled ? Colors.white : Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      );
  }



  Future<void> _saveShowAndFlatten() async {
    final show = context.read<ShowState>().currentShow;
    if (show == null || show.mediaFile.isEmpty) return;

    if (_currentIntersection == null || _intersectW <= 0 || _intersectH <= 0) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No Intersection! Video must intersect matrix to save.")));
       return;
    }

    // 1. Pick Project File
    final projectPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Project & Render',
      fileName: '${show.name}.kshow',
      type: FileType.custom,
      allowedExtensions: ['kshow'],
    );
    
    if (projectPath == null) return;

    // 2. Derive Video Path
    final String videoPath = projectPath.replaceAll(RegExp(r'\.kshow$'), '') + "_media.mp4";

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
             Text("Rendering Video & Saving..."),
          ],
        ),
      ),
    );

    try {
        // 3. Render
        final success = await _performFfmpegRender(show.mediaFile, videoPath, show.mediaTransform, _intersectW, _intersectH, _currentIntersection!);
        
        if (!mounted) return;
        Navigator.pop(context); // Close loader

        if (success) {
           // 4. Calculate New Transform (Center of Intersection)
           final rect = _currentIntersection!; 
           final newTx = rect.center.dx; // Center of Intersection in Matrix Space
           final newTy = rect.center.dy;
           
           // Set temporary overrides to prevent flash of wrong size
           // The new video matches _intersectW/H resolution.
           // Scale 10 applied to THIS resolution yields correct Visual Size (~rect.width)
           if (mounted) {
              setState(() {
                 _overrideWidth = _intersectW;
                 _overrideHeight = _intersectH;
              });
           }
           
           // Scale 10.0 matches the GridSize (1 pixel = 10.0 visual units)
           // This ensures the low-res export looks 1:1 on the grid.
           final newTransform = MediaTransform(
              scaleX: 10.0, 
              scaleY: 10.0, 
              translateX: newTx, 
              translateY: newTy, 
              rotation: 0.0
           );
           
           final state = context.read<ShowState>();
           state.setMediaAndTransform(videoPath, newTransform);
           await state.saveShowAs(projectPath);
           
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Show Saved & Rendered!")));
        } else {
             _showError("Export Failed. See logs.");
        }

    } catch (e) {
       if (mounted) Navigator.pop(context);
       _showError("Save Error: $e");
    }
  }

  Future<bool> _performFfmpegRender(String inputPath, String outputPath, MediaTransform? transform, int targetW, int targetH, Rect intersection) async {
      final t = transform ?? MediaTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0);
      final width = player.state.width;
      final height = player.state.height;
      if (width == null || height == null) return false;

      // Logic from _exportVideo
      final scaledW = width * t.scaleX;
      final scaledH = height * t.scaleY;
      final vidLeft = t.translateX - (scaledW / 2);
      final vidTop = t.translateY - (scaledH / 2);
      
      double cropVisX = intersection.left - vidLeft;
      double cropVisY = intersection.top - vidTop;
      if (cropVisX < 0) cropVisX = 0;
      if (cropVisY < 0) cropVisY = 0;
      
      double cropVisW = intersection.width;
      double cropVisH = intersection.height;
      
      double sourceX = cropVisX / t.scaleX;
      double sourceY = cropVisY / t.scaleY;
      double sourceW = cropVisW / t.scaleX;
      double sourceH = cropVisH / t.scaleY;
      
      if (sourceX + sourceW > width) sourceW = width - sourceX;
      if (sourceY + sourceH > height) sourceH = height - sourceY;
      
      // FFmpeg Chain
      List<String> filters = [];
      filters.add('crop=${sourceW.floor()}:${sourceH.floor()}:${sourceX.floor()}:${sourceY.floor()}');
      
      int outW = (targetW % 2 == 0) ? targetW : targetW - 1;
      int outH = (targetH % 2 == 0) ? targetH : targetH - 1;
      if (outW <= 0) outW = 2;
      if (outH <= 0) outH = 2;

      filters.add('scale=$outW:$outH:flags=lanczos');
      
      List<String> args = [
        '-i', inputPath,
        '-vf', filters.join(','),
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        '-preset', 'medium',
        '-y', outputPath
      ];

      final result = await Process.run('ffmpeg', args);
      if (result.exitCode != 0) {
         debugPrint("FFmpeg Error: ${result.stderr}");
         return false;
      }
      return true;
  }

  void _showError(String msg) {
     showDialog(context: context, builder: (c) => AlertDialog(content: Text(msg), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("OK"))]));
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
