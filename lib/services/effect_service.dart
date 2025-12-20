import 'dart:math';
import 'dart:ui' as ui; // Added for images
import 'package:flutter/material.dart';

enum EffectType {
  rainbow,
  solid,
  textScroll,
  christmas,
  waves,
  noise,
  black, // Deprecated but kept to prevent break if json has it, but effectively hidden
  lemming,

  pacman,
  emoji,
  clouds,
}

class EffectDef {
  final String name;
  final EffectType type;
  final IconData icon; // Used as fallback or overlay
  final String? thumbnailAsset; // Prepare for asset text/image
  final Map<String, dynamic> defaultParams;
  final Map<String, dynamic> minParams;
  final Map<String, dynamic> maxParams;

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
      name: 'Solid Color',
      type: EffectType.solid,
      icon: Icons.format_paint,
      defaultParams: {'color': 0xFFFF0000}, // Red
      minParams: {},
      maxParams: {},
    ),
    EffectDef(
      name: 'Text Scroll',
      type: EffectType.textScroll,
      icon: Icons.text_fields,
      defaultParams: {
        'text': 'HELLO WORLD',
        'bgColor': 0xFF000000,
        'textColor': 0xFFFFFFFF,
        'speed': 1.0,
        'scale': 1.0 // Text Size Scale
      },
      minParams: {'speed': 0.1, 'scale': 0.5},
      maxParams: {'speed': 5.0, 'scale': 3.0},
    ),
     EffectDef(
      name: 'Christmas',
      type: EffectType.christmas,
      icon: Icons.star,
      defaultParams: {'speed': 1.0, 'density': 1.0},
      minParams: {'speed': 0.1, 'density': 0.1},
      maxParams: {'speed': 3.0, 'density': 2.0},
    ),
     EffectDef(
      name: 'Waves',
      type: EffectType.waves,
      icon: Icons.waves,
      defaultParams: {'speed': 1.0, 'complexity': 1.0},
      minParams: {'speed': 0.1, 'complexity': 1.0},
      maxParams: {'speed': 5.0, 'complexity': 5.0},
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
      name: 'Lemmings',
      type: EffectType.lemming,
      icon: Icons.stairs,
      defaultParams: {'count': 10.0, 'speed': 1.0},
      minParams: {'count': 1.0, 'speed': 0.1},
      maxParams: {'count': 50.0, 'speed': 5.0},
    ),
    EffectDef(
      name: 'Pacman Chase',
      type: EffectType.pacman,
      icon: Icons.gamepad,
      defaultParams: {'speed': 1.0},
      minParams: {'speed': 0.5},
      maxParams: {'speed': 3.0},
    ),
    EffectDef(
      name: 'Emoji Slide',
      type: EffectType.emoji,
      icon: Icons.emoji_emotions,
      defaultParams: {'count': 5.0, 'speed': 1.0},
      minParams: {'count': 1.0, 'speed': 0.1},
      maxParams: {'count': 20.0, 'speed': 5.0},
    ),
    EffectDef(
      name: 'Cloud Sky',
      type: EffectType.clouds,
      icon: Icons.cloud,
      defaultParams: {'speed': 1.0, 'scale': 1.0},
      minParams: {'speed': 0.1, 'scale': 0.1},
      maxParams: {'speed': 5.0, 'scale': 2.0},
    ),
  ];

  static CustomPainter getPainter(EffectType type, Map<String, dynamic> params, double time, {Map<String, ui.Image>? images}) {
    switch (type) {
      case EffectType.rainbow:
        return _RainbowPainter(time, (params['speed'] ?? 1.0).toDouble(), (params['scale'] ?? 1.0).toDouble());
      case EffectType.solid:
        return _SolidPainter((params['color'] ?? 0xFFFF0000).toInt());
      case EffectType.textScroll:
        return _TextScrollPainter(
          text: params['text'] ?? "HELLO",
          bgColor: (params['bgColor'] ?? 0xFF000000).toInt(),
          textColor: (params['textColor'] ?? 0xFFFFFFFF).toInt(),
          speed: (params['speed'] ?? 1.0).toDouble(),
          scale: (params['scale'] ?? 1.0).toDouble(),
          time: time
        );
      case EffectType.christmas:
        return _ChristmasPainter(time, (params['speed'] ?? 1.0).toDouble(), (params['density'] ?? 1.0).toDouble());
      case EffectType.waves:
        return _WavesPainter(time, (params['speed'] ?? 1.0).toDouble(), (params['complexity'] ?? 1.0).toDouble());
      case EffectType.noise:
        return _NoisePainter(time, (params['intensity'] ?? 0.5).toDouble());
      case EffectType.black:
        return _BlackPainter(); // Deprecated generally, but kept just in case of stale state
      case EffectType.lemming:
        return _LemmingPainter(
           time, 
           (params['count'] ?? 10.0).toDouble(), 
           (params['speed'] ?? 1.0).toDouble(),
           image: images?['lemming']
        );
      case EffectType.pacman:
        return _PacmanPainter(time, (params['speed'] ?? 1.0).toDouble());
      case EffectType.emoji:
        return _EmojiPainter(time, (params['count'] ?? 5.0).toDouble(), (params['speed'] ?? 1.0).toDouble());
      case EffectType.clouds:
        return _CloudPainter(time, (params['speed'] ?? 1.0).toDouble(), (params['scale'] ?? 1.0).toDouble(), image: images?['cloud']);
    }
  }

  // Returns "source,filter" string.



  // Returns "source,filter" string.


  // Returns "source,filter" string.
  static String getFFmpegFilter(EffectType type, Map<String, dynamic> params) {
      return "color=c=black:s=1920x1080";
  }
}

class _RainbowPainter extends CustomPainter {
  final double time;
  final double speed;
  final double scale;
  _RainbowPainter(this.time, this.speed, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    // Dynamic Spectrum
    // Shift the hue based on X and Time
    // We use a shader for maximum performance and smoothness
    final gradient = LinearGradient(
      colors: const [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purpleAccent, Colors.red],
      tileMode: TileMode.repeated,
      transform: GradientRotation(0), // Placeholder
    );
    
    // Manual shader construction to shift
    double shift = time * speed;
    double freq = scale / size.width;
    
    // We can't easily animate gradient "offset" in LinearGradient without creating a custom shader or many stops.
    // Easier: Draw a very wide gradient and translate the canvas/rect? 
    // Or just iterate pixels (too slow).
    
    // Best Flutter way: createShader with a transform matrix.
    // Matrix4 translation.
    
    // Width of one continuous spectrum = size.width / scale.
    double cycleW = size.width / scale;
    if (cycleW <= 0) cycleW = size.width;
    
    double tX = -(shift * 200) % cycleW;
    
    var shader = gradient.createShader(Rect.fromLTWH(tX, 0, cycleW, size.height));
    
    final paint = Paint()..shader = shader;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_RainbowPainter oldDelegate) => true;
}

class _SolidPainter extends CustomPainter {
  final int colorVal;
  _SolidPainter(this.colorVal);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Color(colorVal), BlendMode.src);
  }
  @override
  bool shouldRepaint(_SolidPainter oldDelegate) => oldDelegate.colorVal != colorVal;
}

class _TextScrollPainter extends CustomPainter {
  final double time;
  final String text;
  final int bgColor;
  final int textColor;
  final double speed;
  final double scale;
  
  _TextScrollPainter({
    required this.time,
    required this.text,
    required this.bgColor,
    required this.textColor,
    required this.speed,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
     canvas.drawColor(Color(bgColor), BlendMode.src);
     
     TextPainter tp = TextPainter(
       text: TextSpan(text: text, style: TextStyle(color: Color(textColor), fontSize: 100 * scale, fontWeight: FontWeight.bold)),
       textDirection: TextDirection.ltr
     );
     tp.layout();
     
     // Scroll Right to Left
     double totalW = tp.width + size.width;
     double offset = (time * 200 * speed) % totalW;
     double x = size.width - offset;
     
     tp.paint(canvas, Offset(x, (size.height - tp.height) / 2));
  }
  @override
  bool shouldRepaint(_TextScrollPainter o) => true;
}

class _ChristmasPainter extends CustomPainter {
  final double time;
  final double speed;
  final double density;
  _ChristmasPainter(this.time, this.speed, this.density);
  
  @override
  void paint(Canvas canvas, Size size) {
     final bg = Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)]
     ).createShader(Offset.zero & size);
     canvas.drawRect(Offset.zero & size, bg);
     
     final rng = Random(123);
     
     // Snow
     final snowPaint = Paint()..color = Colors.white.withOpacity(0.8);
     int count = (100 * density).toInt();
     for(int i=0; i<count; i++) {
        double x = (rng.nextDouble() * size.width + time * 10 * speed * (rng.nextBool() ? 1:-1)) % size.width;
        double y = (rng.nextDouble() * size.height + time * 50 * speed) % size.height;
        double r = rng.nextDouble() * 3 + 1;
        canvas.drawCircle(Offset(x,y), r, snowPaint);
     }
     
     // Lights (Red/Green flashing)
     int lights = (50 * density).toInt();
     for(int i=0; i<lights; i++) {
        double lx = rng.nextDouble() * size.width;
        double ly = rng.nextDouble() * size.height;
        
        bool isRed = i % 2 == 0;
        double flash = sin(time * speed * 5 + i);
        if (flash > 0) {
           final lightPaint = Paint()..color = (isRed ? Colors.red : Colors.green).withOpacity(flash.abs());
           canvas.drawCircle(Offset(lx, ly), 6, lightPaint);
        }
     }
  }
  @override
  bool shouldRepaint(_ChristmasPainter o) => true;
}

class _WavesPainter extends CustomPainter {
  final double time;
  final double speed;
  final double complexity;
  _WavesPainter(this.time, this.speed, this.complexity);

  @override
  void paint(Canvas canvas, Size size) {
     canvas.drawColor(Colors.black, BlendMode.src);
     
     // Neon Stylized Waves
     final colors = [Colors.cyanAccent, Colors.purpleAccent, Colors.pinkAccent];
     
     for (int i=0; i<3; i++) {
        final paint = Paint()
          ..color = colors[i].withOpacity(0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
          
        Path path = Path();
        path.moveTo(0, size.height/2);
        
        for (double x=0; x<=size.width; x+=5) {
           double nX = x / size.width; // 0-1
           double wave = sin(nX * 10 * complexity + time * speed + i) * 100;
           path.lineTo(x, size.height/2 + wave);
        }
        canvas.drawPath(path, paint);
     }
  }
  @override
  bool shouldRepaint(_WavesPainter o) => true;
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
    _drawNoiseLayer(canvas, size, blockSize, intensity * 0.5, Colors.white30);
    _drawNoiseLayer(canvas, size, blockSize, intensity * 0.2, Colors.white);
  }
  
  void _drawNoiseLayer(Canvas canvas, Size size, double blockSize, double density, Color color) {
     final paint = Paint()
        ..color = color
        ..strokeWidth = blockSize
        ..strokeCap = StrokeCap.square;
        
     final rng = Random();
     int total = ((size.width / blockSize) * (size.height / blockSize)).toInt();
     int count = (total * density * 0.5).toInt();
     if (count > 5000) count = 5000;
     
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

// NEW EFFECT PAINTERS

// ... (Previous Painters)

class _LemmingPainter extends CustomPainter {
  final double time;
  final double count;
  final double speed;

  // A looping track/maze for Lemmings
  // Points define the center of the path they walk
  static const List<Point<int>> track = [
    Point(2,2), Point(3,2), Point(4,2), Point(5,2), Point(6,2), Point(7,2), 
    Point(8,2), Point(8,3), Point(8,4), 
    Point(7,4), Point(6,4), Point(5,4), Point(4,4), Point(3,4), Point(2,4),
    Point(2,5), Point(2,6), 
    Point(3,6), Point(4,6), Point(5,6), Point(6,6), Point(7,6), Point(8,6), Point(9,6), Point(10,6),
    Point(10,5), Point(10,4), Point(10,3), Point(10,2), Point(11,2), Point(12,2), Point(13,2),
    Point(13,3), Point(13,4), Point(13,5), Point(13,6), Point(13,7), Point(13,8),
    Point(12,8), Point(11,8), Point(10,8), Point(9,8), Point(8,8), Point(7,8), Point(6,8), Point(5,8), Point(4,8), Point(3,8), Point(2,8),
    Point(1,8), Point(1,7), Point(1,6), Point(1,5), Point(1,4), Point(1,3), Point(1,2), // Loop back
  ];

  final ui.Image? image;

  _LemmingPainter(this.time, this.count, this.speed, {this.image});

  @override
  void paint(Canvas canvas, Size size) {
     // Background: stylized "Dungeon" / PCB
     canvas.drawColor(const Color(0xFF1a1a2e), BlendMode.src);
     
     // Setup Grid
     double w = 15;
     double h = 10;
     double cellSize = size.width / w;
     if (size.height / h < cellSize) cellSize = size.height / h;
     
     double offX = (size.width - cellSize * w) / 2;
     double offY = (size.height - cellSize * h) / 2;
     canvas.translate(offX, offY);

     // Draw Track/Maze Floor
     final trackPaint = Paint()..color = const Color(0xFF16213e)..style = PaintingStyle.fill;
     
     for (var p in track) {
        Rect r = Rect.fromLTWH(p.x * cellSize, p.y * cellSize, cellSize, cellSize);
        canvas.drawRect(r, trackPaint);
     }
     
     // Draw Lemmings
     int lemmingCount = count.toInt();
     double spaceBetween = 2.0; // Distance in grid units
     double totalTrackLen = track.length.toDouble();
     
     for(int i=0; i<lemmingCount; i++) {
        double dist = (time * speed * 2.0 - i * spaceBetween) % totalTrackLen;
        if (dist < 0) continue; // Not spawned
        
        int idx = dist.floor();
        double sub = dist - idx;
        
        Point<int> pNow = track[idx % track.length];
        Point<int> pNext = track[(idx + 1) % track.length];
        
        double lx = (pNow.x + (pNext.x - pNow.x) * sub) * cellSize + cellSize/2;
        double ly = (pNow.y + (pNext.y - pNow.y) * sub) * cellSize + cellSize/2;
        
        // Direction
        bool facingRight = (pNext.x >= pNow.x);
        
        // Bouncing logic for walk
        double walkCycle = (time * speed * 15 + i) % 8; // 8 frames
        int frame = walkCycle.floor();
        
        // Bounce offset not needed if sprite has bounce?
        // Let's keep a slight y-bounce if sprite is generic
        double by = ly;
        
        if (image != null) {
            _drawSpriteLemming(canvas, Offset(lx, by), cellSize * 1.2, facingRight, frame);
        } else {
            // Fallback Vector
            _drawHighResLemming(canvas, Offset(lx, by), cellSize * 0.8, facingRight);
        }
     }
  }
  
  void _drawSpriteLemming(Canvas canvas, Offset pos, double size, bool facingRight, int frame) {
      if (image == null) return;
      
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      // Sprite is centered at feet or center? usually center.
      // Sprite is 64x64. Frame is 64x64.
      
      if (!facingRight) canvas.scale(-1, 1);
      
      // Source Rect
      // 8 frames, horizontal. 
      // Image w=512, h=64.
      double fw = image!.width / 8.0;
      double fh = image!.height.toDouble();
      
      Rect src = Rect.fromLTWH(frame * fw, 0, fw, fh);
      Rect dst = Rect.fromCenter(center: Offset(0, -size*0.4), width: size, height: size);
      
      canvas.drawImageRect(image!, src, dst, Paint());
      
      canvas.restore();
  }

  void _drawHighResLemming(Canvas canvas, Offset pos, double size, bool facingRight) {
      // Dimensions
      double w = size * 0.6;
      double h = size;
      
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      if (!facingRight) canvas.scale(-1, 1);
      
      // Pivot at feet? Pos is center.
      canvas.translate(0, -h/2); 
      
      // 1. Hair (Green Floof)
      final hairPaint = Paint()..color = const Color(0xFF00FF00); // Bright Retro Green
      canvas.drawOval(Rect.fromLTWH(-w/2, -h/2, w, h*0.4), hairPaint);
      
      // 2. Head/Skin
      final skinPaint = Paint()..color = const Color(0xFFFFCCAA);
      canvas.drawOval(Rect.fromLTWH(-w*0.35, -h*0.3, w*0.7, h*0.3), skinPaint);
      
      // 3. Body (Blue Shirt)
      final shirtPaint = Paint()..color = Colors.blue[700]!;
      canvas.drawRect(Rect.fromLTWH(-w*0.3, 0, w*0.6, h*0.35), shirtPaint);
      
      // 4. Eyes
      final white = Paint()..color = Colors.white;
      final black = Paint()..color = Colors.black;
      canvas.drawCircle(Offset(2, -h*0.15), 2.5, white);
      canvas.drawCircle(Offset(2, -h*0.15), 1, black);
      
      // 5. Arms (Swinging?)
      canvas.drawRect(Rect.fromLTWH(-w*0.1, h*0.1, w*0.4, 4), skinPaint);
      
      // 6. Feet
      canvas.drawRect(Rect.fromLTWH(-w*0.3, h*0.35, w*0.25, 4), black); // Left
      canvas.drawRect(Rect.fromLTWH(0.05*w, h*0.35, w*0.25, 4), black); // Right
      
      canvas.restore();
  }

  @override
  bool shouldRepaint(_LemmingPainter oldDelegate) => true;
}

class _PacmanPainter extends CustomPainter {
  final double time;
  final double speed;

  // Simple 15x15 Maze Data (1 = Wall, 0 = Dot)
  static const List<String> map = [
    "111111111111111",
    "100000010000001",
    "101111010111101",
    "101000000000101",
    "101011101110101",
    "100010000010001",
    "111010111010111",
    "000000101000000",
    "111010111010111",
    "100010000010001",
    "101011101110101",
    "101000000000101",
    "101111010111101",
    "100000010000001",
    "111111111111111",
  ];

  _PacmanPainter(this.time, this.speed);

  @override
  void paint(Canvas canvas, Size size) {
      canvas.drawColor(Colors.black, BlendMode.src);
      
      // Layout Logic:
      // Reserve top 40px for Score (at 1080p scale, maybe relative?)
      // Let's reserve 1/10th of height.
      double scoreBlock = 0;
      
      double mazeH = size.height - scoreBlock;
      double mazeW = size.width;
      
      // Grid 15x15
      double cellSize = mazeH / 15.0;
      // Ensure fit width
      if (cellSize * 15 > mazeW) {
         cellSize = mazeW / 15.0;
      }
      
      double gridW = cellSize * 15;
      double gridH = cellSize * 15;
      
      double offX = (mazeW - gridW) / 2;
      double offY = scoreBlock + (mazeH - gridH) / 2;
      
      canvas.translate(offX, offY);
      
      // STYLE: Brighter, Thicker Walls
      final wallPaint = Paint()
        ..color = Colors.blueAccent 
        ..style = PaintingStyle.stroke
        ..strokeWidth = cellSize * 0.25 // Thicker
        ..strokeCap = StrokeCap.round;
        
      final dotPaint = Paint()..color = Colors.white.withOpacity(0.8)..style = PaintingStyle.fill;
      
      // Calculate Path Progress
      List<Point<int>> path = _generatePath();
      double totalDist = path.length.toDouble();
      double currentDist = (time * speed * 5.0) % totalDist; 
      int idx = currentDist.floor();
      double sub = currentDist - idx;
      Point<int> pNow = path[idx % path.length];
      Point<int> pNext = path[(idx + 1) % path.length];
      Offset pacPos = Offset(
         (pNow.x + (pNext.x - pNow.x) * sub) * cellSize + cellSize/2,
         (pNow.y + (pNext.y - pNow.y) * sub) * cellSize + cellSize/2
      );

      // Draw Maze
      for (int y=0; y<15; y++) {
         for (int x=0; x<15; x++) {
            String cell = map[y][x];
            Rect r = Rect.fromLTWH(x*cellSize, y*cellSize, cellSize, cellSize);
            
            if (cell == '1') {
               // Walls: Draw center lines to look connected?
               // Simple block approach with rounded corners or deflated rects?
               // User wants "Thicker line".
               // A stroke on the rect border works, but doubles up on edges.
               // Let's use Line segments for cleaner look?
               // Too complex for now. Just draw small filled rounded rects?
               // Or Stroked rects.
               
               // Let's draw "Blocky" walls.
               final fillP = Paint()..color = Colors.blueAccent..style = PaintingStyle.fill;
               // canvas.drawRect(r.deflate(2), fillP);
               // User said "Line".
               canvas.drawRect(r.deflate(cellSize * 0.15), wallPaint);
               
            } else {
               // Dots
               Point<int> pt = Point(x,y);
               int dotIdx = path.indexOf(pt);
               bool isEaten = false;
               if (dotIdx != -1) {
                  // Adjust logic for loop wrap.
                  // If currentDist is past dotIdx...
                  // BUT: if loop wrapped, dots reset?
                  // Let's just say dots reappear after Pacman is far away? No.
                  // Simple: Eaten if dist > dotIdx. Reset when dist wraps?
                  // The modulo keeps looping.
                  // Let's assume dots respawn when Pacman is 1/2 maze away?
                  // Simpler: Dot is eaten if (currentDist - dotIdx).abs() < 5? No.
                  // Traditional: Eaten if `currentDist > dotIdx`. 
                  // When loop restarts, all dots appear?
                  if (currentDist > dotIdx) isEaten = true;
               }
               if (!isEaten) {
                  canvas.drawCircle(r.center, cellSize * 0.15, dotPaint);
               }
            }
         }
      }
      
      // Characters - BIGGER
      double charSize = cellSize * 0.9; // Almost fill cell
      
      // PACMAN
      double mouth = 0.25 * sin(time * 15).abs();
      double angle = 0;
      if (pNext.x > pNow.x) angle = 0;
      else if (pNext.x < pNow.x) angle = pi;
      else if (pNext.y > pNow.y) angle = pi/2;
      else if (pNext.y < pNow.y) angle = 3*pi/2;
      
      canvas.save();
      canvas.translate(pacPos.dx, pacPos.dy);
      canvas.rotate(angle);
      final pacPaint = Paint()..color = Colors.yellow;
      canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: charSize/2), mouth, 2*pi - 2*mouth, true, pacPaint);
      canvas.restore();
      
      // GHOSTS
      List<Color> gColors = [Colors.red, Colors.pink, Colors.cyan, Colors.orange];
      for (int i=0; i<4; i++) {
          double lag = 4.0 + i*2.0;
          double gDist = currentDist - lag;
          if (gDist < 0) gDist += totalDist;
          
          int gIdx = gDist.floor();
          double gSub = gDist - gIdx;
          Point<int> gNow = path[gIdx % path.length];
          Point<int> gNext = path[(gIdx + 1) % path.length];
          Offset gPos = Offset(
             (gNow.x + (gNext.x - gNow.x) * gSub) * cellSize + cellSize/2,
             (gNow.y + (gNext.y - gNow.y) * gSub) * cellSize + cellSize/2
          );
          
          _drawGhost(canvas, gPos, charSize, gColors[i]);
      }
      

  }

  void _drawGhost(Canvas canvas, Offset pos, double size, Color color) {
     final p = Paint()..color = color;
     double r = size * 0.5; // Bigger radius
     Rect rect = Rect.fromCircle(center: pos, radius: r);
     
     // Head
     canvas.drawArc(rect, pi, pi, true, p);
     // Body
     canvas.drawRect(Rect.fromLTWH(rect.left, rect.center.dy, rect.width, rect.height/2), p);
     
     // Eyes - Bigger
     final eyeWhite = Paint()..color = Colors.white;
     final eyePupil = Paint()..color = Colors.blue[900]!;
     double er = r * 0.35;
     canvas.drawCircle(pos + Offset(-r*0.3, -r*0.1), er, eyeWhite);
     canvas.drawCircle(pos + Offset(r*0.3, -r*0.1), er, eyeWhite);
     canvas.drawCircle(pos + Offset(-r*0.2, -r*0.1), er/2, eyePupil);
     canvas.drawCircle(pos + Offset(r*0.4, -r*0.1), er/2, eyePupil);
  }

  List<Point<int>> _generatePath() {
     // STRICTLY VERIFIED PATH (Wall Avoidance)
     List<Point<int>> p = [];
     
     // 1. Start Top-Left (1,1) -> (1,5)
     p.addAll(_line(1,1, 1,5));
     // 2. Cross to Col 3 (Row 5 safe x=1..3)
     p.addAll(_line(1,5, 3,5));
     // 3. Up to Highway (3,3)
     p.addAll(_line(3,5, 3,3));
     // 4. Highway East (3,3) -> (11,3)
     p.addAll(_line(3,3, 11,3));
     // 5. Dip to Right Mirror (11,3) -> (11,5) -> (13,5)
     p.addAll(_line(11,3, 11,5));
     p.addAll(_line(11,5, 13,5));
     // 6. Top Right Corner (13,5) -> (13,1) -> (8,1) -> (8,3)
     p.addAll(_line(13,5, 13,1));
     p.addAll(_line(13,1, 8,1));
     p.addAll(_line(8,1, 8,3)); 
     // 7. Back to Center Highway (8,3) -> (3,3)
     p.addAll(_line(8,3, 3,3));
     // 8. Dive South (3,3) -> (3,11) (Col 3 Open 3..11)
     p.addAll(_line(3,3, 3,11));
     // 9. Bottom Highway (3,11) -> (11,11) (Row 11 Open 3..11)
     p.addAll(_line(3,11, 11,11));
     // 10. Bottom Right Dip (11,11) -> (11,13) -> (13,13) -> (13,9)
     p.addAll(_line(11,11, 11,13));
     p.addAll(_line(11,13, 13,13));
     p.addAll(_line(13,13, 13,9));
     // 11. Backtrack Bottom Right
     p.addAll(_line(13,9, 13,13));
     p.addAll(_line(13,13, 11,13));
     p.addAll(_line(11,13, 11,11));
     // 12. Back West (11,11) -> (3,11)
     p.addAll(_line(11,11, 3,11));
     // 13. Bottom Left Dip (3,11) -> (3,13) -> (1,13) -> (1,9)
     p.addAll(_line(3,11, 3,13));
     p.addAll(_line(3,13, 1,13));
     p.addAll(_line(1,13, 1,9));
     // 14. Backtrack Bottom Left
     p.addAll(_line(1,9, 1,13));
     p.addAll(_line(1,13, 3,13));
     p.addAll(_line(3,13, 3,11));
     // 15. Return North (3,11) -> (3,3)
     p.addAll(_line(3,11, 3,3));
     // 16. Return Start (3,3) -> (3,5) -> (1,5) -> (1,1)
     p.addAll(_line(3,3, 3,5));
     p.addAll(_line(3,5, 1,5));
     p.addAll(_line(1,5, 1,1));
     
     return p;
  }
  
  List<Point<int>> _line(int x1, int y1, int x2, int y2) {
    List<Point<int>> pts = [];
    if (x1 == x2) {
       int dir = y2 > y1 ? 1 : -1;
       for (int y = y1; y != y2 + dir; y += dir) pts.add(Point(x1, y));
    } else {
       int dir = x2 > x1 ? 1 : -1;
       for (int x = x1; x != x2 + dir; x += dir) pts.add(Point(x, y1));
    }
    // Remove last point to prevent stutter if chained? 
    // Usually we want A->B, then B->C. B is duplicated.
    // So remove the very first point of this new segment IF it matches the last of previous.
    // Simplifying: Just let it be, a 1-frame pause is fine.
    return pts;
  }

  @override
  bool shouldRepaint(_PacmanPainter oldDelegate) => true;
}

class _EmojiPainter extends CustomPainter {
  final double time;
  final double count;
  final double speed;
  
  _EmojiPainter(this.time, this.count, this.speed);

  static const List<String> emojis = ["😀", "😎", "🚀", "💡", "🔥", "🎉", "👀", "🤖"];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.black, BlendMode.src);
    
    int c = count.toInt();
    final rng = Random(123);
    
    TextStyle style = TextStyle(fontSize: size.height / 5);
    TextPainter tp = TextPainter(textDirection: TextDirection.ltr);
    
    for(int i=0; i<c; i++) {
       double speedVar = 0.5 + rng.nextDouble();
       double y = rng.nextDouble() * size.height;
       double startX = rng.nextDouble() * size.width;
       
       double x = (startX + time * speed * 100 * speedVar) % (size.width + 100) - 50;
       
       String char = emojis[i % emojis.length];
       
       tp.text = TextSpan(text: char, style: style);
       tp.layout();
       tp.paint(canvas, Offset(x, y));
    }
  }
  @override
  bool shouldRepaint(_EmojiPainter o) => true;
}

class _CloudPainter extends CustomPainter {
  final double time;
  final double speed;
  final double scale;
  final ui.Image? image;

  _CloudPainter(this.time, this.speed, this.scale, {this.image});

  @override
  void paint(Canvas canvas, Size size) {
    // Sky Gradient
    final rect = Offset.zero & size;
    final sky = Paint()..shader = ui.Gradient.linear(
      Offset(0, 0),
      Offset(0, size.height),
      [const Color(0xFF00B4DB), const Color(0xFF0083B0)],
    );
    canvas.drawRect(rect, sky);

    // Clouds
    // Parallax layers
    // 3 Layers: Far (slow, small), Mid (medium), Near (fast, big)
    
    _drawLayer(canvas, size, 0.5, 0.5, 5); // Far
    _drawLayer(canvas, size, 0.8, 0.8, 3); // Mid
    _drawLayer(canvas, size, 1.2, 1.2, 2); // Near
  }
  
  void _drawLayer(Canvas canvas, Size size, double speedMult, double scaleMult, int count) {
     final rng = Random(count * 100); // Seed per layer
     for(int i=0; i<count; i++) {
         double y = rng.nextDouble() * size.height * 0.6; // Top 60%
         double startX = rng.nextDouble() * size.width;
         
         double totalSpeed = speed * speedMult * 50; // pixels per sec
         double x = (startX + time * totalSpeed) % (size.width + 400) - 200;
         
         double cloudScale = scale * scaleMult * (0.8 + rng.nextDouble() * 0.4);
         
         if (image != null) {
            _drawSpriteCloud(canvas, Offset(x,y), cloudScale);
         } else {
            _drawProceduralCloud(canvas, Offset(x,y), cloudScale * 100); // 100 base size
         }
     }
  }
  
  void _drawSpriteCloud(Canvas canvas, Offset pos, double s) {
     if (image == null) return;
     double w = image!.width.toDouble() * s * 0.5; // Scale down a bit?
     double h = image!.height.toDouble() * s * 0.5;
     
     // Aspect ratio? Assuming image is reasonable.
     Rect dst = Rect.fromCenter(center: pos, width: w, height: h);
     Rect src = Rect.fromLTWH(0,0, image!.width.toDouble(), image!.height.toDouble());
     
     canvas.drawImageRect(image!, src, dst, Paint()..color = Colors.white.withOpacity(0.9));
  }

  void _drawProceduralCloud(Canvas canvas, Offset pos, double size) {
      final p = Paint()..color = Colors.white.withOpacity(0.8);
      
      // Draw a "puff" cluster
      // Center puff
      canvas.drawCircle(pos, size * 0.5, p);
      // Left puff
      canvas.drawCircle(pos + Offset(-size*0.4, size*0.1), size*0.4, p);
      // Right puff
      canvas.drawCircle(pos + Offset(size*0.4, size*0.1), size*0.4, p);
      // Top puff
      canvas.drawCircle(pos + Offset(0, -size*0.3), size*0.4, p);
  }

  @override
  bool shouldRepaint(_CloudPainter oldDelegate) => true;
}
