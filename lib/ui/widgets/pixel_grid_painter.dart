import 'package:flutter/material.dart';
import 'package:kinet_composer/models/show_manifest.dart';

class PixelGridPainter extends CustomPainter {
  final List<Fixture> fixtures;
  final bool drawLabels;
  final double gridSize;

  PixelGridPainter({
      this.fixtures = const [], 
      this.drawLabels = true,
      this.gridSize = 10.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Determine bounds to center if needed, but for now we expect the canvas to be set up correctly
    // or we just draw from 0,0 and let the parent widget scale/position us.

    final fixturePaint = Paint()
      ..color = Colors.blue.withAlpha(100)
      ..style = PaintingStyle.fill;
    
    final borderPaint = Paint()
      ..color = Colors.green.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (var fixture in fixtures) {
      double fw = fixture.width * gridSize;
      double fh = fixture.height * gridSize;
      
      // Draw Bounding Box
      // Assuming 0,0 origin for now
      canvas.drawRect(Rect.fromLTWH(0, 0, fw, fh), borderPaint);

      for (var pixel in fixture.pixels) {
        final rect = Rect.fromLTWH(
          pixel.x * gridSize, 
          pixel.y * gridSize, 
          gridSize, 
          gridSize
        );
        final pixelRect = rect.deflate(1.0);
        
        canvas.drawRect(pixelRect, fixturePaint);
      }
      
      if (drawLabels) {
        final TextSpan span = TextSpan(style: const TextStyle(color: Colors.white, fontSize: 16), text: fixture.name);
        final TextPainter tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
        tp.layout();
        tp.paint(canvas, const Offset(0, -20));
      }
    }
  }

  @override
  bool shouldRepaint(covariant PixelGridPainter oldDelegate) {
    return oldDelegate.fixtures != fixtures || oldDelegate.gridSize != gridSize;
  }
}
