import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../models/show_manifest.dart';
import '../../state/show_state.dart';
import 'package:kinet_composer/ui/widgets/transform_gizmo.dart';
import '../../services/effect_service.dart';
import '../widgets/effect_renderer.dart';
import 'package:kinet_composer/ui/widgets/pixel_grid_painter.dart';
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
        const String ffmpegPath = r'C:\Users\nicua\Documents\Development\ffmpeg-master-latest-win64-gpl-shared\ffmpeg-master-latest-win64-gpl-shared\bin\ffmpeg.exe';
        
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
      
      const String ffmpegPath = r'C:\Users\nicua\Documents\Development\ffmpeg-master-latest-win64-gpl-shared\ffmpeg-master-latest-win64-gpl-shared\bin\ffmpeg.exe';

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

        final transform = _isEditingCrop ? (_tempTransform ?? baseTransform) : baseTransform;

        return Row(
          children: [
            // Main Editor Area
            Expanded(
              child: Container(
                color: Colors.black87,
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
                             if (_isEditingCrop) {
                               setState(() {
                                 _tempTransform = newTransform;
                               });
                             } else {
                               showState.updateTransform(newTransform);
                             }
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

            // Properties Panel
            Container(
              width: 300,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                border: const Border(
                  left: BorderSide(color: Colors.white24),
                ),
              ),
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                   Text("Videos / Effects",
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  
                  // Top Actions
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _pickVideo(context),
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: const Text("Load Video"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => (_selectedEffect != null) ? _exportEffect() : _exportVideo(),
                          icon: const Icon(Icons.save, size: 18),
                          label: const Text("Save Video"),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // EFFECTS LIBRARY
                  const Text("Effects Library", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 80,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: EffectService.effects.map((e) {
                         bool isSelected = _selectedEffect == e.type;
                         return Padding(
                           padding: const EdgeInsets.only(right: 8.0),
                           child: InkWell(
                             onTap: () {
                                setState(() {
                                   _selectedEffect = e.type;
                                   _effectParams = Map.from(e.defaultParams);
                                   // Stop player
                                   if (player.state.playing) player.pause();
                                   _isPlaying = true; // Auto play effect
                                   _isEditingCrop = false; // Reset crop
                                });
                             },
                             child: Container(
                               width: 70,
                               decoration: BoxDecoration(
                                 color: isSelected ? Colors.blueAccent : Colors.grey[800],
                                 borderRadius: BorderRadius.circular(8),
                                 border: isSelected ? Border.all(color: Colors.white) : null,
                               ),
                               child: Column(
                                 mainAxisAlignment: MainAxisAlignment.center,
                                 children: [
                                   Icon(e.icon, color: Colors.white),
                                   const SizedBox(height: 4),
                                   Text(e.name, 
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white, fontSize: 10),
                                      maxLines: 2, overflow: TextOverflow.ellipsis),
                                 ],
                               ),
                             ),
                           ),
                         );
                      }).toList(),
                    ),
                  ),

                  const Divider(color: Colors.white24, height: 20),

                  if (_selectedEffect != null) ...[
                      // EFFECT CONTROLS
                      Row(
                        children: [
                           Expanded(child: Text("Active: ${_selectedEffect!.name.toUpperCase()}", style: const TextStyle(color: Colors.greenAccent))),
                           IconButton(
                             icon: const Icon(Icons.close, color: Colors.grey),
                             onPressed: () => setState(() => _selectedEffect = null),
                             tooltip: "Close Effect",
                           )
                        ],
                      ),
                      const SizedBox(height: 10),
                      ..._effectParams.keys.map((key) {
                           final def = EffectService.effects.firstWhere((e) => e.type == _selectedEffect);
                           double min = def.minParams[key] ?? 0.0;
                           double max = def.maxParams[key] ?? 1.0;
                           
                           return Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               Text("$key: ${_effectParams[key]!.toStringAsFixed(1)}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                               Slider(
                                 value: _effectParams[key]!,
                                 min: min,
                                 max: max,
                                 onChanged: (v) => setState(() => _effectParams[key] = v),
                               ),
                             ],
                           );
                      }),
                      
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: _exportEffect,
                        icon: const Icon(Icons.save_as),
                        label: const Text("Render & Save Effect"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                      ),
                  ] else if (show.mediaFile.isNotEmpty) ...[
                    // ... EXISTING VIDEO UI ...
                    Text("Source: ${show.mediaFile.split(Platform.pathSeparator).last}",
                        style: const TextStyle(color: Colors.grey)),
                    const Divider(color: Colors.white24, height: 20),

                    const Text("Playback", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                         IconButton(
                           icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                           color: Colors.white,
                           onPressed: () => player.playOrPause(),
                         ),
                         IconButton(
                           icon: const Icon(Icons.stop),
                           color: Colors.red,
                           onPressed: () async {
                             await player.seek(Duration.zero);
                             await player.pause();
                           },
                         ),
                      ],
                    ),
                    
                    const Divider(color: Colors.white24, height: 20),
                    const Text("Editing", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    
                    if (_isEditingCrop) ...[
                        // Edit Mode Toggle
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ChoiceChip(
                              label: const Text("Zoom / Scale"),
                              selected: _editMode == EditMode.zoom,
                              onSelected: (v) => setState(() => _editMode = EditMode.zoom),
                            ),
                            ChoiceChip(
                              label: const Text("Crop"),
                              selected: _editMode == EditMode.crop,
                              onSelected: (v) => setState(() => _editMode = EditMode.crop),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Aspect Radio Lock Toggle (Only in Zoom Mode)
                        if (_editMode == EditMode.zoom) ...[
                             Row(
                               children: [
                                  Checkbox(
                                    value: _lockAspectRatio, 
                                    onChanged: (v) => setState(() => _lockAspectRatio = v ?? true),
                                    fillColor: MaterialStateProperty.all(Colors.blueAccent),
                                  ),
                                  const Text("Lock Aspect Ratio", style: TextStyle(color: Colors.white)),
                               ],
                             ),
                             const SizedBox(height: 10),
                        ],

                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  if (_tempTransform != null) {
                                    showState.updateTransform(_tempTransform!);
                                  }
                                  setState(() {
                                    _isEditingCrop = false;
                                    _tempTransform = null;
                                  });
                                },
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                icon: const Icon(Icons.check),
                                label: const Text("Apply"),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _isEditingCrop = false;
                                    _tempTransform = null;
                                  });
                                },
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                icon: const Icon(Icons.close),
                                label: const Text("Cancel"),
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                           padding: EdgeInsets.only(top: 8.0),
                           child: Text("Drag yellow corners to crop. Drag box to move crop.\nResize/Roate video with blue/green handles.", 
                               style: TextStyle(color: Colors.white70, fontSize: 12)),
                        )
                    ] else ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _isEditingCrop = true;
                                final t = show.mediaTransform ?? MediaTransform(
                                  scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0
                                );
                                _tempTransform = (t.crop == null) 
                                   ? MediaTransform(
                                      scaleX: t.scaleX, scaleY: t.scaleY, 
                                      translateX: t.translateX, translateY: t.translateY, 
                                      rotation: t.rotation,
                                      crop: CropInfo(x: 10, y: 10, width: 80, height: 80)
                                     )
                                   : t;
                              });
                            },
                            child: const Text("Edit Video"),
                          ),
                        ),
                        
                        if (transform.crop != null || transform.scaleX != 1 || transform.scaleY != 1 || transform.rotation != 0) ...[
                           const SizedBox(height: 10),
                           SizedBox(
                               width: double.infinity,
                               child: TextButton.icon(
                                 onPressed: () {
                                    showState.updateTransform(MediaTransform(
                                       scaleX: 1, scaleY: 1, translateX: 0, translateY: 0, rotation: 0, crop: null
                                    ));
                                 },
                                 icon: const Icon(Icons.restart_alt, color: Colors.grey),
                                 label: const Text("Reset All", style: TextStyle(color: Colors.grey)),
                               ),
                           )
                        ]
                    ]
                  ] else
                     const Text("No content loaded.", style: TextStyle(color: Colors.white54)),

                ],
              ),
            ),
          ),
          ],
        );
      },
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
