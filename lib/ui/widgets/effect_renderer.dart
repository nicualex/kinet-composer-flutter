import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../services/effect_service.dart';

class EffectRenderer extends StatefulWidget {
  final EffectType? type;
  final Map<String, dynamic> params;
  final bool isPlaying;
  final double initialTime; // NEW

  const EffectRenderer({
    super.key,
    required this.type,
    required this.params,
    this.isPlaying = true,
    this.initialTime = 0.0,
  });

  @override
  State<EffectRenderer> createState() => _EffectRendererState();
}

class _EffectRendererState extends State<EffectRenderer> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _time = 0.0;
  


  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // Helper to load images
  Map<String, ui.Image> _loadedImages = {};
  
  void _loadImages() {
     // No images to load for current effects
  }

  void _loadImageAsset(String path, String key) {
     AssetImage(path).resolve(ImageConfiguration()).addListener(
       ImageStreamListener(
         (Info, _) {
            if (mounted) {
               setState(() {
                  _loadedImages[key] = Info.image;
               });
            }
         },
         onError: (exception, stackTrace) {
           print("Error loading image $path: $exception");
           // Fallback will naturally occur as key won't be in _loadedImages
         }
       )
     );
  }

  @override
  void didUpdateWidget(EffectRenderer oldWidget) {
     super.didUpdateWidget(oldWidget);
     if (widget.type != oldWidget.type) {
        _loadImages();
     }
     if (widget.initialTime != oldWidget.initialTime) {
        // If initialTime changes, we assume we are seeking or rendering.
        setState(() {
           _time = widget.initialTime;
        });
     }
     
     // React to Playing State Change
     if (widget.isPlaying != oldWidget.isPlaying) {
        if (widget.isPlaying) {
           _ticker.start();
        } else {
           _ticker.stop();
        }
     }
  }

  @override
  void initState() {
    super.initState();
    _time = widget.initialTime;
    _ticker = createTicker((elapsed) {
      if (widget.isPlaying) {
        setState(() {
           _time = widget.initialTime + elapsed.inMilliseconds / 1000.0;
        });
      }
    });
    if (widget.isPlaying) _ticker.start();
    _loadImages();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.type == null) {
      return Container(color: Colors.black);
    }

    return ClipRect(
      child: CustomPaint(
        painter: EffectService.getPainter(widget.type!, widget.params, _time, images: _loadedImages),
        child: Container(), 
      ),
    );
  }
}
