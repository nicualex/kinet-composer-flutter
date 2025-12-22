import 'package:flutter/material.dart';

class GridBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Optimized visibility (White on Dark)
    final paintMain = Paint()..color = Colors.white.withOpacity(0.25)..strokeWidth = 1.0;
    final paintSub = Paint()..color = Colors.white.withOpacity(0.1)..strokeWidth = 0.5;

    // Sub Lines (16px = 1 Pixel Stride)
    const double subStep = 16.0;
    const double mainStep = 80.0; // 5x5 sub-blocks (80px)

    // Sub Lines
    for (double x = 0; x < size.width; x += subStep) {
      if (x % mainStep != 0) canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintSub);
    }
    for (double y = 0; y <= size.height; y += subStep) {
      if (y % mainStep != 0) canvas.drawLine(Offset(0, y), Offset(size.width, y), paintSub);
    }
    
    // Main Lines
    for (double x = 0; x <= size.width; x += mainStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintMain);
    }
    for (double y = 0; y <= size.height; y += mainStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintMain);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
