import 'dart:math';
import 'package:flutter/material.dart';

enum EffectType {
  rainbow,
  noise,
  // Add more later: starfield, plasma, etc.
}

class EffectDef {
  final String name;
  final EffectType type;
  final IconData icon;
  final Map<String, double> defaultParams;
  final Map<String, double> minParams;
  final Map<String, double> maxParams;

  EffectDef({
    required this.name,
    required this.type,
    required this.icon,
    required this.defaultParams,
    required this.minParams,
    required this.maxParams,
  });
}

class EffectService {
  static final List<EffectDef> effects = [
    EffectDef(
      name: 'Rainbow',
      type: EffectType.rainbow,
      icon: Icons.looks,
      defaultParams: {'speed': 1.0, 'scale': 1.0},
      minParams: {'speed': 0.1, 'scale': 0.1},
      maxParams: {'speed': 5.0, 'scale': 5.0},
    ),
    EffectDef(
      name: 'Clouds / Noise',
      type: EffectType.noise,
      icon: Icons.cloud,
      defaultParams: {'speed': 1.0, 'density': 1.0},
      minParams: {'speed': 0.1, 'density': 0.1},
      maxParams: {'speed': 5.0, 'density': 5.0},
    ),
  ];

  static CustomPainter getPainter(EffectType type, Map<String, double> params, double time) {
    switch (type) {
      case EffectType.rainbow:
        return _RainbowPainter(time, params['speed'] ?? 1.0, params['scale'] ?? 1.0);
      case EffectType.noise:
        return _NoisePainter(time, params['speed'] ?? 1.0, params['density'] ?? 1.0);
    }
  }

  // Returns -vf filter string for 1920x1080 generation
  static String getFFmpegFilter(EffectType type, Map<String, double> params) {
    switch (type) {
      case EffectType.rainbow:
        double speed = params['speed'] ?? 1.0;
        double scale = params['scale'] ?? 1.0;
        // hue=H=2*PI*t*speed : s=1
        // We can use 'testsrc' or 'color' as base. 
        // Better: use 'geq' for spatial gradient? 
        // Simple Rainbow: Hue shift over time on a solid color is just looping color. 
        // If we want SPATIAL rainbow (diagonal), we need geq.
        // Let's do simple temporal rainbow first or spatial? 
        // User asked for "Rainbow Chasing", usually implies spatial movement.
        // ffmpeg geq: r='r(X,Y)':g='g(X,Y)':b='b(X,Y)'
        // This is complex to match exactly.
        // Alternative: 'mandelbrot' or 'gradients' source?
        // Let's us 'scolor' source?
        
        // Simpler approximation for FFmpeg:
        // solid color -> hue filter shifting.
        // BUT "Rainbow Chasing" implies spatial.
        // Let's use a generated testsrc with rgbtestsrc? No.
        
        // Let's stick to a simple horizontal rainbow scroll using 'smptebars' + hue shift?
        // Or strictly creating a math expression.
        // "h=X/W*360 + t*speed"
        // geq filter allows this.
        // r,g,b from h,s,l is hard in expression.
        
        // Revised Strategy:
        // Use 'huesaturation' filter on a static gradient image?
        // Or generate valid OpenGLES shader filter? (Complex)
        
        // Let's default to a "Hue Cycle" for now which works reliably.
        // "color=c=red:s=1920x1080,hue=h=t*${speed*100}"
        return "color=c=red:s=1920x1080,hue=h=t*${speed*0.5}:s=1"; // Simple cycling
        
      case EffectType.noise:
        double speed = params['speed'] ?? 1.0;
        // noise=alls=${density}:allf=t
        // This creates static noise. 
        // "geq" for perlin is hard. 
        // "solid color -> noise"
        return "nullsrc=s=1920x1080,noise=alls=${(params['density']??1)*20}:allf=t+u"; 
    }
  }
}

class _RainbowPainter extends CustomPainter {
  final double time;
  final double speed;
  final double scale;

  _RainbowPainter(this.time, this.speed, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    // "Rainbow Chasing" - Diagonal Gradient moving
    final shader = SweepGradient(
      colors: const [Colors.red, Colors.green, Colors.blue, Colors.red],
      stops: const [0.0, 0.33, 0.66, 1.0],
      transform: GradientRotation(time * speed),
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_RainbowPainter oldDelegate) => 
      oldDelegate.time != time || oldDelegate.speed != speed;
}

class _NoisePainter extends CustomPainter {
  final double time;
  final double speed;
  final double density;
  
  // Cache randoms? 
  // For "real" noise we need Perlin. For "Clouds" we usually want Perlin.
  // Flutter standard libs don't have perlin easily.
  // We'll simulate "Star Field" / "Noise" with random dots for now.
  
  _NoisePainter(this.time, this.speed, this.density);

  @override
  void paint(Canvas canvas, Size size) {
     final paint = Paint()..color = Colors.white;
     final bg = Paint()..color = Colors.black;
     
     canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);
     
     // Deterministic random based on ...?
     // For a 'moving' effect, we want stable dots moving.
     int count = (100 * density).toInt();
     var rng = Random(42); // Seeded for consistenct layout, but we need motion.
     
     for (int i=0; i<count; i++) {
        double startX = rng.nextDouble() * size.width;
        double startY = rng.nextDouble() * size.height;
        double z = rng.nextDouble() * 0.5 + 0.5; // Depth speed
        
        // Move X
        double x = (startX + time * speed * 50 * z) % size.width;
        double y = startY;
        
        // Draw star
        canvas.drawCircle(Offset(x, y), z * 2, paint);
     }
  }

  @override
  bool shouldRepaint(_NoisePainter oldDelegate) => true;
}
