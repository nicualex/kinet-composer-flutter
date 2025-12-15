import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../services/effect_service.dart';

class EffectRenderer extends StatefulWidget {
  final EffectType? type;
  final Map<String, double> params;
  final bool isPlaying;

  const EffectRenderer({
    super.key,
    required this.type,
    required this.params,
    this.isPlaying = true,
  });

  @override
  State<EffectRenderer> createState() => _EffectRendererState();
}

class _EffectRendererState extends State<EffectRenderer> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _time = 0.0;
  
  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (widget.isPlaying) {
        setState(() {
           _time = elapsed.inMilliseconds / 1000.0;
        });
      }
    });
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.type == null) {
      return Container(color: Colors.black);
    }

    return ClipRect(
      child: CustomPaint(
        painter: EffectService.getPainter(widget.type!, widget.params, _time),
        child: Container(), 
      ),
    );
  }
}
