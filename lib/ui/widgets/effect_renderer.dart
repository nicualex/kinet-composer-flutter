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
     if (widget.type == EffectType.lemming && !_loadedImages.containsKey('lemming')) {
        _loadImageAsset('assets/lemming_sprite.png', 'lemming');
     }
     if (widget.type == EffectType.clouds && !_loadedImages.containsKey('cloud')) {
        _loadImageAsset('assets/cloud_sprite.png', 'cloud');
     }
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
