import 'package:flutter/material.dart';
import 'package:kinet_composer/models/show_manifest.dart';

class PixelGridPainter extends CustomPainter {
  final List<Fixture> fixtures;
  final bool drawLabels;
  final double gridSize;
  final double opacity;

  PixelGridPainter({
      this.fixtures = const [], 
      this.drawLabels = true,
      this.gridSize = 10.0,
      this.opacity = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Determine bounds to center if needed, but for now we expect the canvas to be set up correctly
    // or we just draw from 0,0 and let the parent widget scale/position us.

    // debugPrint("PixelGridPainter: Painting ${fixtures.length} fixtures");

    final fixturePaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.8 * opacity) // Brighter Pixels
      ..style = PaintingStyle.fill;
    
    final borderPaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.5 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (var fixture in fixtures) {
      double fw = fixture.width * gridSize;
      double fh = fixture.height * gridSize;
      
      // Use fixture position for offset
      double startX = fixture.x;
      double startY = fixture.y;
      
      // Handle Rotation
      final bool isRotated = (fixture.rotation % 180) != 0;
      final int w = fixture.width;
      final int h = fixture.height;
      
      // If rotated 90/270, swap W/H loops for bounding box logic, usually visual remains local row/col
      // implementation details depend on how we want to visualize.
      // SetupTab rotates the canvas. Here we are drawing into a single canvas.
      
      // We must rotate the points manually if we are not using canvas.save/rotate.
      // Simple Approach: 
      //    Standard: x*grid, y*grid
      //    Rot 90:   (h-1-y)*grid, x*grid  <-- assuming CW
      // Let's stick to unrotated relative to fixture origin, but rotate the whole block? 
      // Or just iterate standard grid and let the user see the "strip" as defined.
      // But if the fixture is rotated 90 deg in Setup, we want it rotated here.
      
      canvas.save();
      canvas.translate(startX, startY);
      // Determine center of fixture for rotation? 
      // SetupTab uses Transform.rotate on the center.
      // Here we need to match that.
      
      // Calculate center relative to startX,startY
      double cx = (w * gridSize) / 2.0;
      double cy = (h * gridSize) / 2.0;

      // Ideally we rotate around center
      if (fixture.rotation != 0) {
         canvas.translate(cx, cy);
         canvas.rotate(fixture.rotation * 3.14159 / 180);
         canvas.translate(-cx, -cy);
      }

      for (int y = 0; y < h; y++) {
         for (int x = 0; x < w; x++) {
             // 12px box, 4px space (if grid is 16)
             // GridSize is passed in (16.0). 
             // We can just fill almost the whole grid or simulate the led.
             double size = gridSize >= 4 ? gridSize - 4 : gridSize; 
             
             double px = x * gridSize;
             double py = y * gridSize;
             
             canvas.drawRect(Rect.fromLTWH(px, py, size, size), fixturePaint);
         }
      }
      
      canvas.restore();

      /*
      for (var pixel in fixture.pixels) {
        final rect = Rect.fromLTWH(
          startX + (pixel.x * gridSize), 
          startY + (pixel.y * gridSize), 
          gridSize, 
          gridSize
        );
        final pixelRect = rect.deflate(1.0);
        
        canvas.drawRect(pixelRect, fixturePaint);
      }
      */
      
      if (drawLabels) {
        final TextSpan span = TextSpan(style: const TextStyle(color: Colors.white, fontSize: 16), text: fixture.name);
        final TextPainter tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
        tp.layout();
        // Label position might need adjustment if rotated
        canvas.save();
        canvas.translate(startX, startY);
        tp.paint(canvas, const Offset(0, -20));
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant PixelGridPainter oldDelegate) {
    return oldDelegate.fixtures != fixtures || 
           oldDelegate.gridSize != gridSize ||
           oldDelegate.opacity != opacity ||
           oldDelegate.drawLabels != drawLabels;
  }
}
