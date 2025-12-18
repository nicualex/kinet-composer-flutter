import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

enum EffectType {
  rainbow,
  noise,
  black,
  clouds,
  galaxies,
}

class EffectDef {
  final String name;
  final EffectType type;
  final IconData icon; // Used as fallback or overlay
  final String? thumbnailAsset; // Prepare for asset text/image
  final Map<String, double> defaultParams;
  final Map<String, double> minParams;
  final Map<String, double> maxParams;

  EffectDef({
    required this.name,
    required this.type,
    required this.icon,
    this.thumbnailAsset,
    required this.defaultParams,
    required this.minParams,
    required this.maxParams,
  });
}

class EffectService {
  static final List<EffectDef> effects = [
    EffectDef(
      name: 'Rainbow Wave',
      type: EffectType.rainbow,
      icon: Icons.palette,
      defaultParams: {'speed': 1.0, 'scale': 1.0},
      minParams: {'speed': 0.1, 'scale': 0.1},
      maxParams: {'speed': 5.0, 'scale': 5.0},
    ),
    EffectDef(
      name: 'Static Noise',
      type: EffectType.noise,
      icon: Icons.tv,
      defaultParams: {'intensity': 0.5},
      minParams: {'intensity': 0.0},
      maxParams: {'intensity': 1.0},
    ),
    EffectDef(
      name: 'Blackout',
      type: EffectType.black,
      icon: Icons.check_box_outline_blank,
      defaultParams: {},
      minParams: {},
      maxParams: {},
    ),
    EffectDef(
      name: 'Drifting Clouds',
      type: EffectType.clouds,
      icon: Icons.cloud,
      defaultParams: {'density': 0.5, 'speed': 0.2},
      minParams: {'density': 0.1, 'speed': 0.1},
      maxParams: {'density': 1.0, 'speed': 2.0},
    ),
    EffectDef(
      name: 'Galaxy Night',
      type: EffectType.galaxies,
      icon: Icons.auto_awesome,
      defaultParams: {'density': 0.3, 'speed': 0.1},
      minParams: {'density': 0.1, 'speed': 0.0},
      maxParams: {'density': 1.0, 'speed': 1.0},
    ),
  ];

  static CustomPainter getPainter(EffectType type, Map<String, double> params, double time) {
    switch (type) {
      case EffectType.rainbow:
        return _RainbowPainter(time, params['speed'] ?? 1.0, params['scale'] ?? 1.0);
      case EffectType.noise:
        return _NoisePainter(time, params['intensity'] ?? 0.5);
      case EffectType.black:
        return _BlackPainter();
      case EffectType.clouds:
        return _CloudsPainter(time, params['density'] ?? 0.5, params['speed'] ?? 0.2);
      case EffectType.galaxies:
        return _GalaxiesPainter(time, params['density'] ?? 0.3, params['speed'] ?? 0.1);
    }
  }

  // Returns "source,filter" string.
  // The consumer should split by first comma if present.
  static String getFFmpegFilter(EffectType type, Map<String, double> params) {
    switch (type) {
      case EffectType.rainbow:
        double speed = params['speed'] ?? 1.0;
        double scale = params['scale'] ?? 1.0;
        
        // Horizontal Rainbow Wave using GEQ
        // R = 127.5 + 127.5 * sin(2*PI*(X/W)*scale + T*speed)
        // Phase shift for G and B to create rainbow (120 deg = 2.09 rad, 240 deg = 4.18 rad)
        // Note: FFmpeg 'sin' takes radians. 'T' is time in seconds.
        
        // We use 'nullsrc' or 'color=black' as base, but geq generates content, so source doesn't matter much 
        // as long as it has size. "color=c=black:s=1920x1080" is good.
        
        // Ensure scale is at least somewhat visible
        // scale=1.0 means 1 full rainbow cycle across width
        
        final freq = "((X/W)*2*PI*$scale + T*$speed)";
        
        return "color=c=black:s=1920x1080,geq="
               "r='127.5+127.5*sin($freq)':"
               "g='127.5+127.5*sin($freq+2.09)':"
               "b='127.5+127.5*sin($freq+4.18)'";

      case EffectType.noise:
        double intensity = params['intensity'] ?? 0.5;
        // noise filter: alls=strength:allf=strength
        // ranges 0-100? FFmpeg docs say 0 to 100 per component.
        // We map 0.0-1.0 to 0-100.
        int val = (intensity * 100).toInt().clamp(0, 100);
        
        // 't+u' means temporal variance (changes every frame) + uniform noise
        return "color=c=black:s=1920x1080,noise=alls=$val:allf=t+u";
        
      case EffectType.black:
        return "color=c=black:s=1920x1080";
        
      case EffectType.clouds:
        // Approximation using fractal noise (turbulence) if available, or just blurred noise
        // Using 'noise' with low freq isn't easy in vanilla ffmpeg without complex filterchains.
        // We'll use a placeholder 'testsrc' with some processing or just simple noise for now.
        // User asked for "white clouds passing over blue sky".
        // simple: color=blue, noise added?
        // Let's try geq with moving perlin-ish approximation (sine sums)
        return "color=c=skyblue:s=1920x1080,noise=alls=20:allf=t+u"; // Fallback
        
      case EffectType.galaxies:
        // "Galaxies moving slowly over night sky"
        // Black bg, slow white dots (stars)?
        // Noise with high contrast?
        return "color=c=black:s=1920x1080,noise=alls=50:allf=t+u,eq=contrast=20"; // Stars
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
    // Horizontal Repeating Gradient matching the Sine Wave
    // Sine wave peaks at PI/2.
    // We can just use a sliding LinearGradient.
    
    // Offset calculation:
    // T*speed moves the wave.
    // 2*PI corresponds to 1.0 in gradient stops (0-1).
    // So 1.0 offset = 2*PI change.
    
    // We simply shift the alignment?
    // Alignment(-1,0) to Alignment(1,0) is screen width.
    // Gradient repeats.
    
    // Let's rely on standard R-G-B-R gradient stops.
    // And translate it.
    
    // Strategy: Create shader on a virtual rect of width/scale.
    // Then apply a transform to the shader?
    
    final gradient = LinearGradient(
      colors: const [Colors.red, Colors.green, Colors.blue, Colors.red],
      stops: const [0.0, 0.33, 0.66, 1.0],
      tileMode: TileMode.repeated,
    );
    
    // We want the gradient to repeat 'scale' times across 'size.width'.
    // So the "base" gradient should resolve to 'size.width / scale'.
    
    final double cycleWidth = (scale > 0) ? size.width / scale : size.width;
    
    // Matrix4 translation for movement
    // We translate X by time.
    // shift = (time * speed) in Radians.
    // 2*PI Radians = 1 cycleWidth.
    // shiftPixels = (time * speed / (2*PI)) * cycleWidth.
    

    
    // Scale transform? 
    // Easier to just define the rect for createShader?
    // If we createShader on (0,0, cycleWidth, height)
    // and TileMode.repeated, it will fill the whole paint area?
    // Yes.
    

    
    // Apply matrix to shader?
    // LinearGradient has a 'transform' property!
    // But we need to combine sizing and translation.
    
    // Let's use the transform on the context?
    // No, we want the rect to stay put.
    
    // Let's just user the matrix on the shader using a different method?
    // transform property on LinearGradient takes a GradientTransform.
    // We can implement a custom GradientTransform or just use GradientRotation?
    // GradientRotation only rotates.
    
    // Let's just use canvas.translate?
    // If we translate the canvas, the rect moves.
    // We want the texture (pattern) to move inside the rect.
    
    // Solution: Draw a huge rect? No.
    // Solution: Use matrix in createShader? No API for that on Shader object directly in Dart easily?
    // Actually Paint.shader_ is just a shader.
    
    // Backtrack: LinearGradient has `transform`.
    // We can use a custom class `_SlideGradientTransform`?
    // Or just manually construct values?
    // `Alignment` based sliding is easiest.
    
    // width of gradient = 2.0 / scale (in alignment space, -1 to 1 is 2.0).
    // range = 2.0 / scale.
    // start = -1.0 - phase
    // end = start + range
    

    
    // We want to shift LEFT (negative) as time increases to match "wave moving right"?
    // sin(x - t) moves right? sin(x + t) moves left.
    // Our FFmpeg is sin(x + t). Moves LEFT (content flows left).
    // So phase should be subtracted.
    
    // double startAlign = -1.0 - (phase * range); 
    // Wait, phase is "percent of a cycle". 
    // One cycle = 'range' in alignment units.
    
    // Let's re-calculate.
    // Align(-1) is Left. Align(1) is Right.
    // We want 0.0 of gradient to be at Left.
    // If we shift it Left, 0.0 moves to < -1.
    // We need TileMode.repeated.
    
    // Actually, complex Alignment logic with TileMode often breaks or is confusing.
    // Let's trust "GradientRotation" if we could use it? No.
    // Let's use a simpler Painter:
    // Just calculate the colors per pixel? No, slow.
    
    // Let's use the "createShader(Rect)" trick with translation logic manually applied?
    // Actually, if I just create the shader for a shifted Rect?
    // createShader(Rect.fromLTWH(shift, 0, cycleWidth, height))
    // If I say the gradient is defined from 'shift' to 'shift+width', 
    // and I draw on 0..width with Repeated, it should work?
    
    // Valid shader rect:
    // x = -shiftPixels % cycleWidth.
    // w = cycleWidth.
    // This defines the 0..1 of the gradient in matching screen coordinates.
    // If I define the gradient to start at -10 and end at 90.
    // And draw at 0..100.
    // It should repeat.
    
    double shiftX = (time * speed / (2 * pi)) * cycleWidth;
    // We want +t to move left? (sin(kx + wt)).
    // Actually sin(kx + wt) is a wave traveling LEFT (-x direction).
    // So pixels move left.
    // So the start of the gradient (0.0) should move left (negative x).
    
    double startX = -shiftX;
    
    final Paint paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromLTWH(startX, 0, cycleWidth, size.height)
      );
      
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_RainbowPainter oldDelegate) => 
      oldDelegate.time != time || oldDelegate.speed != speed || oldDelegate.scale != scale;
}

class _NoisePainter extends CustomPainter {
  final double time;
  final double intensity;

  _NoisePainter(this.time, this.intensity);

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) {
       canvas.drawColor(Colors.black, BlendMode.src);
       return;
    }
    const double blockSize = 2.0;

    _drawNoiseLayer(canvas, size, blockSize, intensity, Colors.white10);
    // Pass 2: Med
    _drawNoiseLayer(canvas, size, blockSize, intensity * 0.5, Colors.white30);
    // Pass 3: Bright
    _drawNoiseLayer(canvas, size, blockSize, intensity * 0.2, Colors.white);
    
  }
  
  void _drawNoiseLayer(Canvas canvas, Size size, double blockSize, double density, Color color) {
     final paint = Paint()
        ..color = color
        ..strokeWidth = blockSize
        ..strokeCap = StrokeCap.square;
        
     final rng = Random();
     // Estimate count
     int total = ((size.width / blockSize) * (size.height / blockSize)).toInt();
     int count = (total * density * 0.5).toInt(); // Adjust density
     
     if (count > 5000) count = 5000; // Cap for performance
     
     List<Offset> points = [];
     for(int i=0; i<count; i++) {
        points.add(Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height));
     }
     
     canvas.drawPoints(ui.PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(_NoisePainter oldDelegate) => true; 
}

class _BlackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.black, BlendMode.src);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CloudsPainter extends CustomPainter {
  final double time;
  final double density;
  final double speed;
  
  _CloudsPainter(this.time, this.density, this.speed);
  
  @override
  void paint(Canvas canvas, Size size) {
     // Blue Sky
     canvas.drawColor(Colors.lightBlue[300]!, BlendMode.src);
     
     // procedural cloud blobs
     final paint = Paint()..color = Colors.white.withOpacity(0.4)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
     final rng = Random(42); // Seeded for consistence layout, moves by time
     
     int count = (20 * density).toInt();
     for(int i=0; i<count; i++) {
        double w = 100 + rng.nextDouble() * 200;
        double h = 50 + rng.nextDouble() * 100;
        double y = rng.nextDouble() * size.height;
        
        // Move X
        double startX = rng.nextDouble() * size.width;
        double x = (startX + time * speed * 20) % (size.width + 400) - 200;
        
        canvas.drawOval(Rect.fromLTWH(x, y, w, h), paint);
     }
  }
  @override
  bool shouldRepaint(_CloudsPainter oldDelegate) => true;
}

class _GalaxiesPainter extends CustomPainter {
  final double time;
  final double density;
  final double speed;
  
  _GalaxiesPainter(this.time, this.density, this.speed);
  
  @override
  void paint(Canvas canvas, Size size) {
     canvas.drawColor(Colors.black, BlendMode.src);
     
     // Stars
     final paint = Paint()..color = Colors.white;
     final rng = Random(123);
     
     // Background stars (static-ish)
     int count = (500 * density).toInt();
     List<Offset> stars = [];
     for(int i=0; i<count; i++) {
        stars.add(Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height));
     }
     paint.strokeWidth = 1.0;
     canvas.drawPoints(ui.PointMode.points, stars, paint);
     
     // Moving Galaxies (Blobs/Spirals)
     paint.strokeWidth = 0;
     paint.color = Colors.purple.withOpacity(0.3);
     paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
     
     int galCount = (5 * density).toInt() + 1;
     for(int i=0; i<galCount; i++) {
         double w = 200; 
         double h = 150;
         double y = rng.nextDouble() * size.height;
         double startX = rng.nextDouble() * size.width;
         double x = (startX + time * speed * 10) % (size.width + 400) - 200;
         
         canvas.drawOval(Rect.fromLTWH(x, y, w, h), paint);
     }
  }
  @override
  bool shouldRepaint(_GalaxiesPainter oldDelegate) => true;
}
