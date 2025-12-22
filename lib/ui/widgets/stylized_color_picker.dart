import 'dart:math';
import 'package:flutter/material.dart';

class StylizedColorPicker extends StatefulWidget {
  final Color pickerColor;
  final ValueChanged<Color> onColorChanged;

  const StylizedColorPicker({
    super.key,
    required this.pickerColor,
    required this.onColorChanged,
  });

  @override
  State<StylizedColorPicker> createState() => _StylizedColorPickerState();
}

class _StylizedColorPickerState extends State<StylizedColorPicker> {
  late HSVColor _currentHsv;

  @override
  void initState() {
    super.initState();
    _currentHsv = HSVColor.fromColor(widget.pickerColor);
  }

  @override
  void didUpdateWidget(covariant StylizedColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pickerColor != widget.pickerColor) {
      _currentHsv = HSVColor.fromColor(widget.pickerColor);
    }
  }

  void _onHueChanged(double hue) {
    setState(() {
      _currentHsv = _currentHsv.withHue(hue);
    });
    widget.onColorChanged(_currentHsv.toColor());
  }

  void _onSatValChanged(double sat, double val) {
    setState(() {
      _currentHsv = _currentHsv.withSaturation(sat).withValue(val);
    });
    widget.onColorChanged(_currentHsv.toColor());
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Hue Ring
          SizedBox(
            width: 260,
            height: 260,
            child: _HueRing(
              hue: _currentHsv.hue,
              onHueChanged: _onHueChanged,
            ),
          ),

          // 2. SV Box (Centered)
          SizedBox(
            width: 140, // 54% of 260 approx
            height: 140,
            child: _SatValBox(
              hsv: _currentHsv,
              onChanged: _onSatValChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _HueRing extends StatefulWidget {
  final double hue; // 0..360
  final ValueChanged<double> onHueChanged;

  const _HueRing({required this.hue, required this.onHueChanged});

  @override
  State<_HueRing> createState() => _HueRingState();
}

class _HueRingState extends State<_HueRing> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) => _handleGesture(details.localPosition, context),
      onPanDown: (details) => _handleGesture(details.localPosition, context),
      child: CustomPaint(
        painter: _HueRingPainter(hue: widget.hue),
      ),
    );
  }

  void _handleGesture(Offset localPos, BuildContext context) {
    final center = Offset(130, 130); // 260/2
    final dx = localPos.dx - center.dx;
    final dy = localPos.dy - center.dy;
    
    // Check if touch is roughly on ring? 
    // Ring radius is outer 130, inner 100?
    // Let's assume user intends to touch ring if outside the box area.
    final dist = sqrt(dx*dx + dy*dy);
    if (dist < 80) return; // Touch inside box area, ignore (let box handle it if they were separate widgets, but here Stack priority matters)
    
    // Calculate angle
    double angle = atan2(dy, dx); // -pi to pi
    // Convert to 0..360 starting from Right (Red) usually?
    // atan2: 0 is Right (East), PI/2 is Down (South).
    // Hue wheel usually: Red(0) -> Yellow(60) etc.
    // If standard wheel, Red is at 0 degrees.
    
    double hue = angle * 180 / pi;
    if (hue < 0) hue += 360;
    
    widget.onHueChanged(hue);
  }
}

class _HueRingPainter extends CustomPainter {
  final double hue;

  _HueRingPainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final innerRadius = outerRadius - 30; // 30px thick ring

    // Draw Spectrum
    // Sweep Gradient
    final gradient = SweepGradient(
      colors: const [
        Color(0xFFFF0000),
        Color(0xFFFFFF00),
        Color(0xFF00FF00),
        Color(0xFF00FFFF),
        Color(0xFF0000FF),
        Color(0xFFFF00FF),
        Color(0xFFFF0000), 
      ],
    );

    final paint = Paint()
      ..shader = gradient.createShader(Rect.fromCircle(center: center, radius: outerRadius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 30;

    canvas.drawCircle(center, outerRadius - 15, paint);
    
    // Draw Indicator (White Rect on Ring)
    // Position based on hue
    double radians = hue * pi / 180;
    double r = outerRadius - 15;
    double ix = center.dx + r * cos(radians);
    double iy = center.dy + r * sin(radians);
    
    final indPaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3;
    
    canvas.save();
    canvas.translate(ix, iy);
    canvas.rotate(radians); // Rotate to align with ring tangent? Or just radial?
    // User image shows a Rectangle perpendicular to radius? 
    // Actually user image shows a small rectangle ON the ring using the ring status.
    // Let's draw a simple box.
    canvas.drawRect(const Rect.fromLTWH(-6, -10, 12, 20), indPaint..style = PaintingStyle.stroke..strokeWidth=2..color=Colors.white);
    canvas.drawRect(const Rect.fromLTWH(-6, -10, 12, 20), indPaint..style = PaintingStyle.fill..color=Colors.white.withOpacity(0.2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HueRingPainter old) => old.hue != hue;
}

class _SatValBox extends StatefulWidget {
  final HSVColor hsv;
  final Function(double sat, double val) onChanged;

  const _SatValBox({required this.hsv, required this.onChanged});

  @override
  State<_SatValBox> createState() => _SatValBoxState();
}

class _SatValBoxState extends State<_SatValBox> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) => _handleGesture(details.localPosition),
      onPanDown: (details) => _handleGesture(details.localPosition),
      child: CustomPaint(
        painter: _SatValPainter(hsv: widget.hsv),
      ),
    );
  }

  void _handleGesture(Offset pos) {
    // 140x140 box
    double s = (pos.dx / 140.0).clamp(0.0, 1.0);
    double v = 1.0 - (pos.dy / 140.0).clamp(0.0, 1.0); // Y is inverted for Value
    widget.onChanged(s, v);
  }
}

class _SatValPainter extends CustomPainter {
  final HSVColor hsv;

  _SatValPainter({required this.hsv});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    
    // 1. Base Hue Color (Top Right corner effectively? No, pure Hue is S=1 V=1)
    // We compose gradients.
    // Base: White (TopLeft) to Hue (TopRight)? 
    // Std Implementation:
    // Layer 1: Horizontal Gradient (White -> Hue)
    // Layer 2: Vertical Gradient (Transparent -> Black)
    
    // 1. Horizontal: White -> Current Hue (S=1, V=1)
    final hueColor = HSVColor.fromAHSV(1.0, hsv.hue, 1.0, 1.0).toColor();
    final horz = LinearGradient(
      colors: [Colors.white, hueColor],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
    canvas.drawRect(rect, Paint()..shader = horz.createShader(rect));
    
    // 2. Vertical: Transparent -> Black
    final vert = const LinearGradient(
      colors: [Colors.transparent, Colors.black],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
    canvas.drawRect(rect, Paint()..shader = vert.createShader(rect));
    
    // 3. Indicator Circle
    double ix = hsv.saturation * size.width;
    double iy = (1.0 - hsv.value) * size.height;
    
    final indPaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2;
    canvas.drawCircle(Offset(ix, iy), 6, indPaint);
    // Inner fill matches color?
    canvas.drawCircle(Offset(ix, iy), 6, Paint()..color=hsv.toColor());
    // Inner contrast ring
    canvas.drawCircle(Offset(ix, iy), 7, Paint()..color=Colors.black26..style=PaintingStyle.stroke..strokeWidth=1);
  }

  @override
  bool shouldRepaint(_SatValPainter old) => old.hsv != hsv;
}
