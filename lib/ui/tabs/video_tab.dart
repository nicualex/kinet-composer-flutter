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

class VideoTab extends StatefulWidget {
  const VideoTab({super.key});

  @override
  State<VideoTab> createState() => _VideoTabState();
}

class _VideoTabState extends State<VideoTab> {
  late final Player player;
  late final VideoController controller;
  
  String? _loadedFilePath;
  
  bool _isEditingCrop = false;
  MediaTransform? _tempTransform;

  bool _isPlaying = false;
  late final StreamSubscription<bool> _playingSubscription;

  bool _pendingAutoFit = false;
  late final StreamSubscription<int?> _widthSubscription;
  late final StreamSubscription<int?> _heightSubscription;

  // NEW: Aspect Ratio Lock State
  bool _lockAspectRatio = true;
  EditMode _editMode = EditMode.zoom;

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

    // Auto-Fit Listener
    _widthSubscription = player.stream.width.listen((w) => _checkAutoFit());
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
           _isEditingCrop = false;
           _tempTransform = null;
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
      if (_loadedFilePath != null) {
         player.stop();
         _loadedFilePath = null;
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
               _isEditingCrop = false;
               _tempTransform = null;
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
        // Corrected path - removed duplicate folder
        const String ffmpegPath = r'C:\Users\nicua\Documents\Development\ffmpeg-master-latest-win64-gpl-shared\bin\ffmpeg.exe';
        
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
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text("Exporting Video..."),
            SizedBox(height: 10),
            Text("This process creates a new video file with your transformations applied. It may take several minutes depending on the video length and resolution.", 
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );

    try {
      final baseT = show.mediaTransform ?? MediaTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0);
      final t = (_isEditingCrop && _tempTransform != null) ? _tempTransform! : baseT;
      
      final width = player.state.width;
      final height = player.state.height;

      List<String> filters = [];

      // A. Crop
      if (t.crop != null && width != null && height != null) {
        int cw = (width * t.crop!.width / 100).floor();
        int ch = (height * t.crop!.height / 100).floor();
        int cx = (width * t.crop!.x / 100).floor();
        int cy = (height * t.crop!.y / 100).floor();
        
        if (cw % 2 != 0) cw--;
        if (ch % 2 != 0) ch--;
        
        filters.add('crop=$cw:$ch:$cx:$cy');
      }

      // B. Scale
      if (t.scaleX != 1.0 || t.scaleY != 1.0) {
        filters.add('scale=trunc(iw*${t.scaleX}/2)*2:trunc(ih*${t.scaleY}/2)*2');
      }

      // C. Rotate
      if (t.rotation != 0.0) {
        filters.add('rotate=${t.rotation}:ow=rotw(${t.rotation}):oh=roth(${t.rotation}):c=none');
      }

      String filterString = filters.join(',');
      
      // Corrected path - removed duplicate folder
      const String ffmpegPath = r'C:\Users\nicua\Documents\Development\ffmpeg-master-latest-win64-gpl-shared\bin\ffmpeg.exe';

      List<String> args = [
        '-i', show.mediaFile,
      ];
      if (filterString.isNotEmpty) {
        args.addAll(['-vf', filterString]);
      }
      
      args.addAll([
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        '-preset', 'fast',
        '-y', outputPath
      ]);

      debugPrint("FFmpeg Command: $ffmpegPath ${args.join(' ')}");

      final result = await Process.run(ffmpegPath, args);
      
      if (mounted) {
        Navigator.pop(context); // Hide loader
        if (result.exitCode == 0) {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Video Exported Successfully!")));
             
             setState(() {
               _isEditingCrop = false;
               _tempTransform = null;
             });
             
             if (outputPath != null) {
                context.read<ShowState>().updateMedia(outputPath);
             }
        } else {
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Export Failed. Exit: ${result.exitCode}")));
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
                      // GRID BACKGROUND
                      if (show.fixtures.isNotEmpty)
                        LayoutBuilder(
                          builder: (context, constraints) {
                             // Determine total grid size
                             double maxWidth = 0;
                             double maxHeight = 0;
                             const double pxSize = 10.0;
                             for (var f in show.fixtures) {
                               maxWidth = (f.width * pxSize > maxWidth) ? f.width * pxSize : maxWidth;
                               maxHeight = (f.height * pxSize > maxHeight) ? f.height * pxSize : maxHeight;
                             }
                             
                             if (maxWidth == 0 || maxHeight == 0) return const SizedBox.shrink();

                             return Opacity(
                               opacity: 0.8, // More visible background
                               child: Center(
                                 child: FittedBox(
                                   fit: BoxFit.contain,
                                   child: SizedBox(
                                     width: maxWidth,
                                     height: maxHeight,
                                     child: CustomPaint(
                                       painter: PixelGridPainter(
                                          fixtures: show.fixtures, 
                                          drawLabels: false,
                                          gridSize: pxSize
                                       ),
                                     ),
                                   ),
                                 ),
                               ),
                             );
                          },
                        ),
                      
                      // We show Gizmo if media present OR we are previewing an effect
                      if (show.mediaFile.isNotEmpty || _selectedEffect != null)
                        TransformGizmo(
                          transform: transform,
                          isCropMode: _isEditingCrop,
                          editMode: _editMode,
                          lockAspect: _lockAspectRatio,
                          onUpdate: (newTransform) {
                               showState.updateTransform(newTransform);
                          },
                          // CHILD SELECT
                          child: (_selectedEffect != null) 
                              ? AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: EffectRenderer(
                                      type: _selectedEffect, 
                                      params: _effectParams,
                                      isPlaying: _isPlaying
                                  )
                                )
                              : (transform.crop != null && !_isEditingCrop)
                                  ? ClipRect(
                                      clipper: PercentageClipper(transform.crop!),
                                      child: AspectRatio(
                                        aspectRatio: 16 / 9,
                                        child: Video(controller: controller),
                                      ),
                                    )
                                  : AspectRatio(
                                      aspectRatio: 16 / 9,
                                      child: Video(controller: controller),
                                    ),
                        )
                      else
                        const Center(
                          child: Text(
                            "No video loaded.\nUse 'Load Video' on the right panel.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54),
                          ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   // 1. Header
                   Text("Project", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 4),
                   Text(show.name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 24),

                   // 2. Primary Actions (Grid)
                   GridView.count(
                     crossAxisCount: 2,
                     crossAxisSpacing: 10,
                     mainAxisSpacing: 10,
                     shrinkWrap: true, // Vital for nesting in Column
                     childAspectRatio: 1.3,
                     children: [
                        _buildModernButton(
                          icon: Icons.folder_open, 
                          label: "Load Video", 
                          color: const Color(0xFF90CAF9), // Pastel Blue
                          onTap: () => _pickVideo(context)
                        ),
                        _buildModernButton(
                          icon: Icons.save, 
                          label: "Save Video", 
                          color: const Color(0xFFA5D6A7), // Pastel Green
                          isEnabled: show.mediaFile.isNotEmpty || _selectedEffect != null,
                          onTap: () => (_selectedEffect != null) ? _exportEffect() : _exportVideo()
                        ),
                        // Full width transfer button? Or just another tile.
                        _buildModernButton(
                          icon: Icons.upload_file, 
                          label: "Transfer", 
                          color: const Color(0xFFCE93D8), // Pastel Purple
                          isEnabled: show.mediaFile.isNotEmpty,
                          onTap: _showTransferDialog
                        ),
                     ],
                   ),
                   const SizedBox(height: 32),

                   // 2.5 Playback Controls
                   if (show.mediaFile.isNotEmpty) ...[
                      Text("PLAYBACK", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
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

                   // 3. Edit Modes
                   if (show.mediaFile.isNotEmpty) ...[
                      Text("EDIT TOOLS", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildToggle(Icons.zoom_in, "Zoom/Pan", _isEditingCrop && _editMode == EditMode.zoom, () {
                             setState(() {
                               if (_isEditingCrop && _editMode == EditMode.zoom) {
                                 _isEditingCrop = false;
                               } else {
                                 _isEditingCrop = true;
                                 _editMode = EditMode.zoom;
                               }
                             });
                          }),
                          const SizedBox(width: 8),
                          _buildToggle(Icons.crop, "Crop", _isEditingCrop && _editMode == EditMode.crop, () {
                             setState(() {
                               if (_isEditingCrop && _editMode == EditMode.crop) {
                                 _isEditingCrop = false;
                               } else {
                                 // Initialize default crop if null
                                 if (show.mediaTransform?.crop == null) {
                                    final t = show.mediaTransform ?? MediaTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0);
                                    showState.updateTransform(MediaTransform(
                                       scaleX: t.scaleX, scaleY: t.scaleY, 
                                       translateX: t.translateX, translateY: t.translateY, 
                                       rotation: t.rotation,
                                       crop: CropInfo(x: 10, y: 10, width: 80, height: 80)
                                    ));
                                 }
                                 
                                 _isEditingCrop = true;
                                 _editMode = EditMode.crop;
                               }
                             });
                          }),
                        ],
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
                       
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
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
                        ),
                      ),
                   ] else ...[
                       Text("EFFECTS LIBRARY", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                       const SizedBox(height: 12),
                       Expanded(
                         child: ListView(
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
                       ),
                   ],

                  ],
              ),
            ),
          ],
        );
      },
    );
  }

  // MARK: - UI Helpers

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

  Widget _buildToggle(IconData icon, String label, bool isActive, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
             padding: const EdgeInsets.symmetric(vertical: 12),
             decoration: BoxDecoration(
               color: isActive ? Colors.white : Colors.white10,
               borderRadius: BorderRadius.circular(8),
             ),
             child: Column(
               children: [
                 Icon(icon, color: isActive ? Colors.black : Colors.white70, size: 20),
                 const SizedBox(height: 4),
                 Text(label, style: TextStyle(color: isActive ? Colors.black : Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
               ],
             ),
          ),
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
