import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../services/render_service.dart';
import '../../state/show_state.dart';
import 'package:provider/provider.dart';

import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit/media_kit.dart';

class RenderDialog extends StatefulWidget {
  final GlobalKey repaintBoundaryKey;
  final Map<LayerTarget, Player> players;

  const RenderDialog({super.key, required this.repaintBoundaryKey, required this.players});

  @override
  State<RenderDialog> createState() => _RenderDialogState();
}

class _RenderDialogState extends State<RenderDialog> {
  bool _isRendering = false;
  double _progress = 0.0;
  String _status = "Ready";
  
  // Settings
  // Defaults Enforced: 30 FPS, High Quality (interpolated)
  
  @override
  Widget build(BuildContext context) {
    final showState = context.read<ShowState>();
    final matrix = showState.matrixConfig; 

    // Default dimensions from Matrix
    int outW = matrix.width; 
    int outH = matrix.height; 
    
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      title: const Text("Export Video (30fps High Quality)", style: TextStyle(color: Colors.white, fontSize: 16)),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             if (_isRendering) ...[
                LinearProgressIndicator(value: _progress, backgroundColor: Colors.white10, color: Colors.blueAccent),
                const SizedBox(height: 16),
                Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 13)),
             ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                  child: Text("Resolution: ${outW}x${outH}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Render will use High Quality settings (CRF 23, Bicubic Softening) at 30 FPS.",
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
             ]
          ],
        ),
      ),
      actions: [
        if (!_isRendering)
          TextButton(
             onPressed: () => Navigator.of(context).pop(),
             child: const Text("Cancel"),
          ),
        if (!_isRendering)
          ElevatedButton(
             style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
             onPressed: () async {
                String? outPath = await FilePicker.platform.saveFile(
                   dialogTitle: "Save Video",
                   fileName: "${showState.currentShowPath.split('/').last.split('.').first}_composite.mp4",
                   allowedExtensions: ['mp4'],
                );
                
                if (outPath != null) {
                   if (!outPath.endsWith('.mp4')) outPath += ".mp4";
                   _startRender(showState, outPath, outW, outH);
                }
             },
             child: const Text("Render Video"),
          ),
      ],
    );
  }

  void _startRender(ShowState showState, String path, int w, int h) async {
     setState(() {
        _isRendering = true;
        _status = "Initializing...";
        _progress = 0.0;
     });
     
     final service = RenderService(showState, widget.repaintBoundaryKey);
     service.onProgress = (s, p) {
        if (mounted) setState(() { _status = s; _progress = p; });
     };
     
     try {
       await service.renderShow(
         outputPath: path,
         width: w,
         height: h,
         fps: 30, // Enforced Default
         motionInterpolation: true, // Enforced Default
         players: widget.players,
       );
       if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Render Complete!")));
       }
     } catch (e) {
       if (mounted) {
          setState(() { _status = "Error: $e"; _isRendering = false; });
       }
     }
  }
}
