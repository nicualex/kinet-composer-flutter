import 'dart:math';
import 'dart:ui' as ui; // Added for images
import 'package:flutter/material.dart';

enum EffectType {
  rainbow,
  rainbowRipple,
  solid,
  textScroll,
  christmas,
  matrix,
  pacman,
  bioGhosts,
  alchemy,
  goldenSmoke,
  arrival,
  spaceShooters,
  tetris,
  bokeh,
  flowField,
  reactionDiffusion,
  aurora,
  geometric,
  // REMOVED: clubShadows, bioluminescence (Deep Sea)
}

class EffectDef {
  final String name;
  final EffectType type;
  final IconData icon; // Used as fallback or overlay
  final String? thumbnailAsset; // Prepare for asset text/image
  final Map<String, dynamic> defaultParams;
  final Map<String, dynamic> minParams;
  final Map<String, dynamic> maxParams;
  final Map<String, List<String>>? enumOptions;

  EffectDef({
    required this.name,
    required this.type,
    required this.icon,
    this.thumbnailAsset,
    required this.defaultParams,
    required this.minParams,
    required this.maxParams,
    this.enumOptions,
  });
}

class EffectService {
  static final List<EffectDef> effects = [
    EffectDef(
      name: 'Rainbow Wave',
      type: EffectType.rainbow,
      icon: Icons.palette,
      defaultParams: {'speed': 1.0, 'scale': 1.0, 'angle': 45.0},
      minParams: {'speed': 0.1, 'scale': 0.1, 'angle': 0.0},
      maxParams: {'speed': 5.0, 'scale': 5.0, 'angle': 180.0},
    ),
    EffectDef(
      name: 'Rainbow Ripple',
      type: EffectType.rainbowRipple,
      icon: Icons.wifi_tethering, // Radial
      defaultParams: {'speed': 1.0, 'scale': 1.0},
      minParams: {'speed': 0.1, 'scale': 0.1},
      maxParams: {'speed': 5.0, 'scale': 5.0},
    ),
    EffectDef(
      name: 'Solid Color',
      type: EffectType.solid,
      icon: Icons.format_paint,
      defaultParams: {'color': 0xFF00FFFF}, // Cyan Default
      minParams: {},
      maxParams: {},
    ),
        EffectDef(
      name: 'Text Scroll',
      type: EffectType.textScroll,
      icon: Icons.text_fields,
      defaultParams: {
        'text': 'T', // White Capital T
        'bgColor': 0xFF000000,
        'textColor': 0xFFFFFFFF,
        'speed': 0.0,
        'fontSize': 40.0, // Text Font Size (10-100)
        'transparent': 0.0, // 0=Opaque, 1=Transparent
        'font': 'Roboto',
      },
      minParams: {'speed': 0.0, 'fontSize': 20.0, 'transparent': 0.0},
      maxParams: {'speed': 5.0, 'fontSize': 200.0, 'transparent': 1.0},
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
      name: 'Pacman Chase',
      type: EffectType.pacman,
      icon: Icons.gamepad,
      defaultParams: {'speed': 1.0, 'transparent': 0.0},
      minParams: {'speed': 0.5, 'transparent': 0.0},
      maxParams: {'speed': 3.0, 'transparent': 1.0},
    ),
    EffectDef(
      name: 'Bio Ghosts',
      type: EffectType.bioGhosts,
      icon: Icons.blur_on,
      defaultParams: {'speed': 1.0, 'count': 5.0, 'color': 0xFF00FFFF, 'trail': 10.0}, 
      minParams: {'speed': 0.0, 'count': 1.0, 'trail': 0.0},
      maxParams: {'speed': 3.0, 'count': 20.0, 'trail': 100.0},
    ),
    // REMOVED: Deep Sea
    EffectDef(
      name: 'Alchemy',
      type: EffectType.alchemy,
      icon: Icons.science,
      defaultParams: {'speed': 1.0, 'turbulence': 1.0},
      minParams: {'speed': 0.1, 'turbulence': 0.1},
      maxParams: {'speed': 3.0, 'turbulence': 5.0},
    ),

    EffectDef(
      name: 'Golden Smoke',
      type: EffectType.goldenSmoke,
      icon: Icons.waves, 
      defaultParams: {'speed': 1.0, 'echoDelay': 3.0, 'brightness': 1.0, 'density': 1.0, 'bgColor': 0xFF101010, 'transparent': 0.0},
      minParams: {'speed': 0.1, 'echoDelay': 0.5, 'brightness': 0.1, 'density': 0.1, 'transparent': 0.0},
      maxParams: {'speed': 3.0, 'echoDelay': 10.0, 'brightness': 4.0, 'density': 3.0, 'transparent': 1.0},
    ),
    EffectDef(
      name: 'Matrix Rain',
      type: EffectType.matrix,
      icon: Icons.terminal, 
      defaultParams: {'speed': 1.0, 'scale': 0.6, 'transparent': 0.0}, // Scale 0.6 for 3 columns in Thumbnail
      minParams: {'speed': 0.1, 'scale': 0.5, 'transparent': 0.0},
      maxParams: {'speed': 3.0, 'scale': 6.0, 'transparent': 1.0},
    ),
    EffectDef(
      name: 'Lichtenberg Effect',
      type: EffectType.arrival,
      icon: Icons.bolt, 
      defaultParams: {'speed': 1.0, 'flow': 1.0, 'invert': 0.0, 'duration': 1.0, 'scale': 1.0},
      minParams: {'speed': 0.1, 'flow': 0.1, 'invert': 0.0, 'duration': 0.0, 'scale': 0.5},
      maxParams: {'speed': 3.0, 'flow': 5.0, 'invert': 1.0, 'duration': 5.0, 'scale': 3.0},
    ),
    // REMOVED: Club Shadows
    EffectDef(
      name: 'Space Shooters',
      type: EffectType.spaceShooters,
      icon: Icons.rocket_launch,
      defaultParams: {'speed': 1.0, 'transparent': 0.0},
      minParams: {'speed': 0.1, 'transparent': 0.0},
      maxParams: {'speed': 5.0, 'transparent': 1.0},
    ),
    EffectDef(
      name: 'Tetris',
      type: EffectType.tetris,
      icon: Icons.grid_view,
      defaultParams: {'speed': 1.0, 'transparent': 0.0},
      minParams: {'speed': 0.1, 'transparent': 0.0},
      maxParams: {'speed': 5.0, 'transparent': 1.0},
    ),
    EffectDef(
       name: 'Bokeh & Bloom',
       type: EffectType.bokeh,
       icon: Icons.lens_blur, // Represents Bokeh well
       defaultParams: {'speed': 1.0, 'density': 10.0, 'blur': 1.0, 'transparent': 0.0},
       minParams: {'speed': 0.0, 'density': 1.0, 'blur': 0.1, 'transparent': 0.0},
       maxParams: {'speed': 3.0, 'density': 30.0, 'blur': 3.0, 'transparent': 1.0},
    ),

    EffectDef(
       name: 'Digital Silk (Flow)',
       type: EffectType.flowField,
       icon: Icons.wind_power,
       defaultParams: {'speed': 1.0, 'turbulence': 1.0, 'trace': 5.0, 'transparent': 0.0},
       minParams: {'speed': 0.1, 'turbulence': 0.1, 'trace': 1.0, 'transparent': 0.0},
       maxParams: {'speed': 3.0, 'turbulence': 5.0, 'trace': 20.0, 'transparent': 1.0},
    ),
    EffectDef(
       name: 'Biological Growth',
       type: EffectType.reactionDiffusion,
       icon: Icons.fingerprint,
       defaultParams: {'speed': 1.0, 'feed': 0.055, 'kill': 0.062, 'transparent': 0.0},
       minParams: {'speed': 0.0, 'feed': 0.010, 'kill': 0.045, 'transparent': 0.0},
       maxParams: {'speed': 5.0, 'feed': 0.100, 'kill': 0.100, 'transparent': 1.0},
    ),
    EffectDef(
       name: 'Generative Aurora',
       type: EffectType.aurora,
       icon: Icons.landscape, 
       defaultParams: {'speed': 1.0, 'roughness': 1.0, 'colors': 0.0, 'transparent': 0.0},
       minParams: {'speed': 0.1, 'roughness': 0.0, 'colors': 0.0, 'transparent': 0.0},
       maxParams: {'speed': 3.0, 'roughness': 5.0, 'colors': 2.0, 'transparent': 1.0},
       enumOptions: {
          'colors': ['Northern (Green/Teal)', 'Southern (Purple/Pink)', 'Solar (Gold/Red)'],
       }
    ),
    EffectDef(
      name: 'Geometric Shapes',
      type: EffectType.geometric,
      icon: Icons.category,
      defaultParams: {
        'speed': 1.0,
        'shape': 0.0, // Index into enumOptions
        'direction': 0.0, // Index into enumOptions
        'size': 20.0, 
        'count': 20.0,
        'spacing': 60.0,
        'color': 0xFFFFFFFF,
        'transparent': 0.0
      },
      minParams: {'speed': 0.0, 'shape': 0.0, 'direction': 0.0, 'size': 1.0, 'count': 1.0, 'spacing': 10.0, 'transparent': 0.0},
      maxParams: {'speed': 5.0, 'shape': 3.0, 'direction': 3.0, 'size': 200.0, 'count': 200.0, 'spacing': 500.0, 'transparent': 1.0},
      enumOptions: {
         // Radio Button Options
         'shape': ['Line', 'Rectangle', 'Triangle', 'Circle'],
         'direction': ['Left', 'Right', 'Up', 'Down'],
      }
    ),
  ];

  static CustomPainter getPainter(EffectType type, Map<String, dynamic> params, double time, {Map<String, ui.Image>? images}) {
    switch (type) {
      case EffectType.rainbow:
        return _RainbowPainter(
          time, 
          (params['speed'] ?? 1.0).toDouble(), 
          (params['scale'] ?? 1.0).toDouble(),
          (params['angle'] ?? 45.0).toDouble()
        );
      case EffectType.geometric:
        return _GeometricPainter(
           time: time,
           speed: (params['speed'] ?? 1.0).toDouble(),
           shape: (params['shape'] ?? 0.0).toDouble(),
           direction: (params['direction'] ?? 0.0).toDouble(),
           sizeParam: (params['size'] ?? 20.0).toDouble(),
           spacing: (params['spacing'] ?? 60.0).toDouble(),
           count: (params['count'] ?? 20.0).toDouble(),
           color: (params['color'] ?? 0xFFFFFFFF).toInt(),
           transparent: (params['transparent'] ?? 0.0).toDouble(),
        );
      case EffectType.rainbowRipple:
        return _RainbowRipplePainter(
           time, 
           (params['speed'] ?? 1.0).toDouble(), 
           (params['scale'] ?? 1.0).toDouble()
        );
      case EffectType.solid:
        return _SolidPainter((params['color'] ?? 0xFFFF0000).toInt());
      case EffectType.textScroll:
        return _TextScrollPainter(
          text: params['text'] ?? "HELLO",
          bgColor: (params['bgColor'] ?? 0xFF000000).toInt(),
          textColor: (params['textColor'] ?? 0xFFFFFFFF).toInt(),
          speed: (params['speed'] ?? 1.0).toDouble(),
          fontSize: (params['fontSize'] ?? 40.0).toDouble(),
          transparent: (params['transparent'] ?? 0.0).toDouble(),
          font: params['font'] ?? 'Roboto',
          time: time
        );
      case EffectType.christmas:
        return _ChristmasPainter(time, (params['speed'] ?? 1.0).toDouble(), (params['density'] ?? 1.0).toDouble());
      case EffectType.pacman:
        return _PacmanPainter(
           time, 
           (params['speed'] ?? 1.0).toDouble(),
           (params['transparent'] ?? 0.0).toDouble()
        );
      case EffectType.bioGhosts:
        return _BioGhostsPainter(
           time, 
           (params['speed'] ?? 1.0).toDouble(), 
           (params['count'] ?? 10.0).toDouble(),
           (params['trail'] ?? 5.0).toDouble(), 
           params['color'] 
        );
      case EffectType.alchemy:
        return _AlchemyPainter(
          time,
          (params['speed'] ?? 1.0).toDouble(),
          (params['turbulence'] ?? 1.0).toDouble(),
        );
      case EffectType.goldenSmoke:
        return _GoldenSmokePainter(
          time,
          (params['speed'] ?? 1.0).toDouble(),
          (params['echoDelay'] ?? 3.0).toDouble(),
          (params['brightness'] ?? 1.0).toDouble(),
          (params['density'] ?? 1.0).toDouble(),
          (params['bgColor'] ?? 0xFF101010).toInt(),
          (params['transparent'] ?? 0.0).toDouble(),
        );
      case EffectType.matrix:
         return _MatrixPainter(
           time,
           (params['speed'] ?? 1.0).toDouble(),
           (params['scale'] ?? 1.0).toDouble(),
           (params['transparent'] ?? 0.0).toDouble(),
         );
      case EffectType.arrival:
          return _ArrivalPainter(
            time,
            (params['speed'] ?? 1.0).toDouble(),
            (params['flow'] ?? 1.0).toDouble(), 
            (params['invert'] ?? 0.0).toDouble(),
            (params['duration'] ?? 1.0).toDouble(),
            (params['scale'] ?? 1.0).toDouble(),
          );
      case EffectType.spaceShooters:
          return _SpaceShootersPainter(
             time,
             (params['speed'] ?? 1.0).toDouble(),
             (params['transparent'] ?? 0.0).toDouble()
          );
      case EffectType.tetris:
          return _TetrisPainter(
             time,
             (params['speed'] ?? 1.0).toDouble(),
             (params['transparent'] ?? 0.0).toDouble()
          );
      case EffectType.bokeh:
          return _BokehPainter(
             time,
             (params['speed'] ?? 1.0).toDouble(),
             (params['density'] ?? 10.0).toDouble(),
             (params['blur'] ?? 1.0).toDouble(),
             (params['transparent'] ?? 0.0).toDouble(),
          );
      case EffectType.flowField:
          return _FlowFieldPainter(
             time,
             (params['speed'] ?? 1.0).toDouble(),
             (params['turbulence'] ?? 1.0).toDouble(),
             (params['trace'] ?? 5.0).toDouble(),
             (params['transparent'] ?? 0.0).toDouble(),
          );
      case EffectType.reactionDiffusion:
          return _ReactionDiffusionPainter(
             time,
             (params['speed'] ?? 1.0).toDouble(),
             (params['feed'] ?? 0.055).toDouble(),
             (params['kill'] ?? 0.062).toDouble(),
             (params['transparent'] ?? 0.0).toDouble(),
          );
      case EffectType.aurora:
          return _AuroraPainter(
             time,
             (params['speed'] ?? 1.0).toDouble(),
             (params['roughness'] ?? 1.0).toDouble(),
             (params['colors'] ?? 0.0).toDouble(),
             (params['transparent'] ?? 0.0).toDouble(),
          );
      default:
         return _SolidPainter(Colors.black.value);
    }
  }

  // Returns "source,filter" string.



  // Returns "source,filter" string.


  // Returns "source,filter" string.
  static String getFFmpegFilter(EffectType type, Map<String, dynamic> params) {
      return "color=c=black:s=1920x1080";
  }
}



// --- FLOW FIELD PAINTER ---
// --- REACTION DIFFUSION PAINTER ---
// --- AURORA PAINTER ---
class _AuroraPainter extends CustomPainter {
  final double time;
  final double speed;
  final double roughness;
  final double colorMode; // 0, 1, 2
  final double transparent;

  _AuroraPainter(this.time, this.speed, this.roughness, this.colorMode, this.transparent);

  @override
  void paint(Canvas canvas, Size size) {
     if (transparent > 0.9) return;
     
     // 1. Background (Dark Night Sky)
     if (transparent < 0.1) {
       final bg = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [
             Color(0xFF0B1026), // Deep Space Blue
             Color(0xFF2B32B2), // Horizon Blue
          ],
          stops: [0.0, 1.0]
       ).createShader(Offset.zero & size);
       canvas.drawRect(Offset.zero & size, Paint()..shader = bg);
     }
     
     // 2. Curtains
     // We assume ~3 layers of curtains
     int layers = 3;
     
     List<Color> palette;
     if (colorMode < 0.5) {
        // Northern (Green/Teal)
        palette = [Colors.greenAccent, Colors.tealAccent, Colors.cyan];
     } else if (colorMode < 1.5) {
        // Southern (Purple/Pink)
        palette = [Colors.purpleAccent, Colors.pinkAccent, Colors.deepPurple];
     } else {
        // Solar (Red/Gold)
        palette = [Colors.orangeAccent, Colors.redAccent, Colors.yellowAccent];
     }
     
     final paint = Paint()
       ..maskFilter = MaskFilter.blur(BlurStyle.normal, 15.0) // Soft light
       ..blendMode = BlendMode.plus; // Additive blending
       
     
     for(int i=0; i<layers; i++) {
        paint.color = palette[i % palette.length].withOpacity(0.4);
        
        Path path = Path();
        
        // Base sine wave parameters
        double freq = 2.0 + i;
        double amp = size.height * 0.2;
        double phase = time * speed * (0.5 + i * 0.2);
        
        path.moveTo(0, size.height); 
        
        // Draw the top edge of the curtain
        for(double x = 0; x <= size.width; x+= 20.0) {
           
           // Domain Warping (Simulated by adding noise to 'x' or 'phase')
           // We use simple layered sines to approximate Perlin noise
           double n = sin(x * 0.01 * roughness + phase) 
                    + sin(x * 0.03 * roughness - phase * 0.5) * 0.5;
           
           double yBase = size.height * 0.6 - (i * 50);
           
           double y = yBase + n * amp;
           
           // Vertical spikes (Auroral pillars)
           // n2 is high frequency noise
           double n2 = sin(x * 0.1 + time * speed) * cos(x * 0.05 + phase);
           y -= n2.abs() * 50.0 * roughness; 
           
           path.lineTo(x, y);
        }
        
        path.lineTo(size.width, size.height);
        path.lineTo(0, size.height);
        path.close();
        
        canvas.drawPath(path, paint);
     }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => true;
}

class _ReactionDiffusionPainter extends CustomPainter {
  final double time;
  final double speed;
  final double feed;
  final double kill;
  final double transparent;

  _ReactionDiffusionPainter(this.time, this.speed, this.feed, this.kill, this.transparent);

  static final _RDState _state = _RDState();

  @override
  void paint(Canvas canvas, Size size) {
    if (transparent > 0.9) return;
    
    // Background
    canvas.drawColor(Colors.black, BlendMode.src);
    
    // Update Simulation
    _state.update(speed, feed, kill, size);

    // Render Grid
    // Since we are simulating on a small grid (e.g. 64x64), we scale it up.
    // Drawing individual rects is faster than Image decode on CPU for this specific dynamic use case
    // unless we use pixel buffer (which is harder in pure CustomPainter).
    
    final Paint paint = Paint()..style = PaintingStyle.fill;
    
    double cellW = size.width / _RDState.width;
    double cellH = size.height / _RDState.height;
    
    // Optimization: Draw larger batches? scaling?
    // For now, simple rects at 60x60 is 3600 calls. manageable.
    
    for (int y = 0; y < _RDState.height; y++) {
       for (int x = 0; x < _RDState.width; x++) {
          double val = _state.gridB[x][y];
          double valA = _state.gridA[x][y];
          
          // Visualization: simple B concentration mapping
          // B - A gives interesting outlines
          double v = (val - valA + 0.5).clamp(0.0, 1.0);
          
          // Color Mapping (Teal/Cyan/Purple bio look)
          // High B = White/Cyan, Low B = Black/Purple
          if (val > 0.1) {
             paint.color = Color.lerp(
                Colors.deepPurple, 
                Colors.cyanAccent, 
                (val * 3).clamp(0.0, 1.0)
             )!;
             
             canvas.drawRect(Rect.fromLTWH(x * cellW, y * cellH, cellW + 0.5, cellH + 0.5), paint);
          }
       }
    }
  }

  @override
  bool shouldRepaint(_ReactionDiffusionPainter old) => true;
}

class _RDState {
  static const int width = 60;
  static const int height = 40; // 3:2 Aspect approx
  
  // A = usually 1.0, B = usually 0.0 initially
  List<List<double>> gridA = List.generate(width, (_) => List.filled(height, 1.0));
  List<List<double>> gridB = List.generate(width, (_) => List.filled(height, 0.0));
  
  List<List<double>> nextA = List.generate(width, (_) => List.filled(height, 1.0));
  List<List<double>> nextB = List.generate(width, (_) => List.filled(height, 0.0));
  
  // Diffusion rates
  double da = 1.0;
  double db = 0.5;
  
  bool initialized = false;

  void init() {
     // Seed with some B
     Random r = Random();
     for(int i=0; i<50; i++) { // Drop 50 blobs
       int cx = r.nextInt(width);
       int cy = r.nextInt(height);
       for(int x=cx-2; x<cx+2; x++) {
          for(int y=cy-2; y<cy+2; y++) {
             if (x>=0 && x<width && y>=0 && y<height) gridB[x][y] = 1.0;
          }
       }
     }
     initialized = true;
  }

  void update(double speed, double feed, double kill, Size size) {
     if (!initialized) init();

     // Simulation loop (Gray-Scott)
     // To look good, we often need multiple iterations per frame
     int iterations = (2 * speed).toInt().clamp(1, 10);
     
     for (int i=0; i<iterations; i++) {
        swap();
        calc(feed, kill);
     }
  }
  
  void swap() {
    var tempA = gridA; gridA = nextA; nextA = tempA;
    var tempB = gridB; gridB = nextB; nextB = tempB;
  }
  
  void calc(double f, double k) {
      // 3x3 convolution weights
      // 0.05  0.2  0.05
      // 0.2   -1   0.2
      // 0.05  0.2  0.05
      
      for(int x=1; x<width-1; x++) {
         for(int y=1; y<height-1; y++) {
            double a = gridA[x][y];
            double b = gridB[x][y];
            
            double laplaceA = 
               (gridA[x-1][y] * 0.2) +
               (gridA[x+1][y] * 0.2) +
               (gridA[x][y-1] * 0.2) +
               (gridA[x][y+1] * 0.2) +
               (gridA[x-1][y-1] * 0.05) +
               (gridA[x+1][y-1] * 0.05) +
               (gridA[x-1][y+1] * 0.05) +
               (gridA[x+1][y+1] * 0.05) - 
               (a);
               
            double laplaceB = 
               (gridB[x-1][y] * 0.2) +
               (gridB[x+1][y] * 0.2) +
               (gridB[x][y-1] * 0.2) +
               (gridB[x][y+1] * 0.2) +
               (gridB[x-1][y-1] * 0.05) +
               (gridB[x+1][y-1] * 0.05) +
               (gridB[x-1][y+1] * 0.05) +
               (gridB[x+1][y+1] * 0.05) - 
               (b);
               
            // Gray-Scott Formula
            // A' = A + (Da * laplaceA - A*B*B + feed*(1-A)) * dt
            // B' = B + (Db * laplaceB + A*B*B - (k+feed)*B) * dt
            
            double abb = a * b * b;
            
            nextA[x][y] = (a + (da * laplaceA - abb + f * (1 - a))).clamp(0.0, 1.0);
            nextB[x][y] = (b + (db * laplaceB + abb - (k + f) * b)).clamp(0.0, 1.0);
         }
      }
  }
}

class _FlowFieldPainter extends CustomPainter {
  final double time;
  final double speed;
  final double turbulence;  // Noise Scale
  final double trace;       // Trail Length
  final double transparent;

  _FlowFieldPainter(this.time, this.speed, this.turbulence, this.trace, this.transparent);

  static final _FlowState _state = _FlowState();

  @override
  void paint(Canvas canvas, Size size) {
    if (transparent > 0.9) return;
    if (transparent < 0.1) canvas.drawColor(Colors.black, BlendMode.src);

    _state.update(time, speed, turbulence, size);

    // Draw Particles
    // Use a complex gradient or simply varying opacity trails
    
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.5;

    for (var p in _state.particles) {
       // Color based on velocity/angle for "Silk" sheen
       // Or simple white/cyan gradient
       double speedFactor = (p.vx.abs() + p.vy.abs()) * 0.5; // 0..2 approx
       int alpha = (100 + speedFactor * 100).toInt().clamp(0, 255);
       
       paint.color = Color.fromARGB(alpha, 200, 220, 255); // Silky Blue-White

       // Draw Trail (approximated by drawing line from prevPos)
       // For longer "Trace" effect, we would need history buffers. 
       // For now, we simulate "Digital Silk" by drawing a longer streak contrary to velocity.
       
       Offset pos = Offset(p.x, p.y);
       Offset tail = pos - Offset(p.vx * trace, p.vy * trace);
       
       canvas.drawLine(tail, pos, paint);
    }
  }

  @override
  bool shouldRepaint(_FlowFieldPainter old) => true;
}

class _FlowState {
  List<_FlowParticle> particles = [];
  double lastTime = 0.0;
  
  // Simple Pseudo-Noise (Simplex approx)
  double noise(double x, double y, double z) {
     // Very basic seeded hash function for "deterministic" random field
     // In a real app, use `fast_noise`. Here we use sin/cos combos.
     return sin(x * 0.1 + z) * cos(y * 0.1 + z * 0.5) + sin(x * 0.3 + y * 0.3 + z);
  }

  void update(double time, double speed, double turbulence, Size size) {
     double dt = time - lastTime;
     if (dt < 0 || dt > 1.0) { reset(size); dt = 0.016; }
     lastTime = time;

     // Populate
     int targetCount = 1000;
     if (particles.length < targetCount) {
        // Init batch
        for(int i=0; i<targetCount - particles.length; i++) {
           particles.add(_FlowParticle(
             Random().nextDouble() * size.width,
             Random().nextDouble() * size.height
           ));
        }
     }

     // Physics
     double scale = 0.05 * turbulence;
     double z = time * 0.2 * speed;

     for (var p in particles) {
        // Calculate Angle from Noise
        double angle = noise(p.x * scale, p.y * scale, z) * pi * 4;
        
        // Add force
        double force = 2.0; 
        p.vx += cos(angle) * force * dt;
        p.vy += sin(angle) * force * dt;
        
        // Friction / Velocity Limit
        p.vx *= 0.95;
        p.vy *= 0.95;
        
        // Move
        p.x += p.vx * speed * 2.0;
        p.y += p.vy * speed * 2.0;
        
        // Wrap
        if (p.x < 0) p.x += size.width;
        if (p.x > size.width) p.x -= size.width;
        if (p.y < 0) p.y += size.height;
        if (p.y > size.height) p.y -= size.height;
     }
  }

  void reset(Size size) {
     particles.clear();
  }
}

class _FlowParticle {
  double x, y;
  double vx = 0;
  double vy = 0;
  _FlowParticle(this.x, this.y);
}

// --- BOKEH PAINTER ---
class _BokehPainter extends CustomPainter {
  final double time;
  final double speed;
  final double density;
  final double blur;
  final double transparent;

  _BokehPainter(this.time, this.speed, this.density, this.blur, this.transparent);

  static final _BokehState _state = _BokehState();

  @override
  void paint(Canvas canvas, Size size) {
    if (transparent > 0.9) return;

    // Background (Deep atmospheric fade)
    if (transparent < 0.1) {
       canvas.drawColor(Colors.black, BlendMode.src);
    }

    _state.update(time, speed, density.toInt() * 5, size); // Multiplier for density

    // Additive Blending for "Bloom"
    // We use a separate layer or just draw primitives with BlendMode.plus
    
    final paint = Paint()
      ..blendMode = BlendMode.plus
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 20.0 * blur);

    for (var p in _state.particles) {
       paint.color = p.color.withOpacity(0.4); // Low opacity for accumulation
       canvas.drawCircle(Offset(p.x, p.y), p.size * (0.8 + 0.2 * sin(time + p.id)), paint);
    }
  }

  @override
  bool shouldRepaint(_BokehPainter old) => true;
}

class _BokehState {
  List<_BokehParticle> particles = [];
  double lastTime = 0.0;

  void update(double time, double speed, int targetCount, Size size) {
     double dt = time - lastTime;
     if (dt < 0 || dt > 1.0) { reset(size); dt = 0.016; }
     lastTime = time;

     // Manage Population
     while (particles.length < targetCount) {
        particles.add(_BokehParticle.random(size));
     }
     while (particles.length > targetCount) {
        particles.removeLast();
     }

     // Update Physics
     for (var p in particles) {
        p.y -= p.speed * speed * dt * 50.0; // Float upwards
        p.x += sin(time * 0.5 + p.id) * speed * dt * 10.0; // Gentle sway

        // Wrap around
        if (p.y < -p.size * 2) {
           p.y = size.height + p.size;
           p.x = Random().nextDouble() * size.width;
        }
     }
  }

  void reset(Size size) {
     particles.clear();
  }
}

class _BokehParticle {
  double x, y;
  double size;
  double speed;
  Color color;
  int id;

  _BokehParticle(this.x, this.y, this.size, this.speed, this.color, this.id);

  factory _BokehParticle.random(Size size) {
     final r = Random();
     // Warm/Dreamy Palette (Golds, Peaches, Soft Whites)
     final colors = [
        Color(0xFFFFD700), // Gold
        Color(0xFFFFE5B4), // Peach
        Color(0xFFFFC0CB), // Pink
        Color(0xFFE6E6FA), // Lavender
        Color(0xFF87CEEB), // Sky Blue (Accent)
     ];
     
     return _BokehParticle(
        r.nextDouble() * size.width,
        r.nextDouble() * size.height,
        r.nextDouble() * 50.0 + 20.0, // Size 20-70
        r.nextDouble() * 0.5 + 0.2,   // Speed
        colors[r.nextInt(colors.length)],
        r.nextInt(10000)
     );
  }
}

// --- SPACE SHOOTERS PAINTER ---
class _SpaceShootersPainter extends CustomPainter {
  final double time;
  final double speed;
  final double transparent;

  _SpaceShootersPainter(this.time, this.speed, this.transparent);

  // Sprites (1 = pixel, 0 = empty)
  static const List<String> _invader1 = [
    "001000100",
    "000101000",
    "001111100",
    "011010110",
    "111111111",
    "101111101",
    "101000101",
    "000101000",
  ];
  
  static const List<String> _invader2 = [
    "00011000",
    "00111100",
    "01111110",
    "11011011",
    "11111111",
    "00100100",
    "01011010",
    "10100101",
  ];

  static const List<String> _invader2_move = [
    "00011000",
    "00111100",
    "01111110",
    "11011011",
    "11111111",
    "00100100",
    "01000010",
    "00100100",
  ];

  static const List<String> _turnipShip = [
    "000010000",
    "000111000",
    "001111100",
    "011101110",
    "111111111",
    "111111111",
    "111111111",
    "110000011",
  ];

  static const List<String> _explosion = [
    "1000001",
    "0100010",
    "0010100",
    "0001000",
    "0010100",
    "0100010",
    "1000001",
  ];

  // Singleton Game State to persist across frames
  static final _SpaceGameState _gameState = _SpaceGameState();

  void _drawSprite(Canvas canvas, List<String> sprite, Offset pos, double pxSize, Color color) {
     final paint = Paint()..color = color;
     for (int y=0; y<sprite.length; y++) {
        for (int x=0; x<sprite[y].length; x++) {
           if (x < sprite[y].length && sprite[y][x] == '1') {
              canvas.drawRect(
                 Rect.fromLTWH(pos.dx + x*pxSize, pos.dy + y*pxSize, pxSize, pxSize), 
                 paint
              );
           }
        }
     }
  }

  @override
  void paint(Canvas canvas, Size size) {
     // Update Game State
     _gameState.update(time, speed, size);

     if (transparent < 0.5) {
        // Space Background: Deep Blue/Black gradient
        final bg = LinearGradient(
           begin: Alignment.topCenter, end: Alignment.bottomCenter,
           colors: [Color(0xFF000000), Color(0xFF0D0D1A)]
        ).createShader(Offset.zero & size);
        canvas.drawRect(Offset.zero & size, Paint()..shader = bg);
     }
     


      // Pixel Scale (Doubled from 9.0 to 18.0)
     double px = 18.0;
     double shooterPx = 18.0; // Same as aliens
     
     // Draw Player
     // Height of ship is 8 * 18 = 144.
     // size.height - 144 - margin (10)
     double shipY = size.height - 144 - 10;
     if (shipY < 200) shipY = size.height - 50; 
     
     _drawSprite(canvas, _turnipShip, Offset(_gameState.playerX - 4.5*shooterPx, shipY), shooterPx, Colors.greenAccent);
     
     // Draw Bullets
     final shotPaint = Paint()..color = Colors.yellowAccent ..strokeWidth = px ..strokeCap = StrokeCap.square;
     for (var b in _gameState.bullets) {
        canvas.drawRect(Rect.fromLTWH(b.dx - px/2, b.dy, px, px*2), shotPaint);
     }
     
     // Draw Enemies
     for (var e in _gameState.enemies) {
        if (!e.active) continue;
        if (e.exploding) {
           _drawSprite(canvas, _explosion, Offset(e.x - 3.5*px, e.y), px, Colors.redAccent);
        } else {
           List<String> sprite = e.type == 0 ? _invader1 : 
                                (e.frame == 0 ? _invader2 : _invader2_move);
           // Apply formation offset
           double ex = e.x + _gameState.formationX;
           _drawSprite(canvas, sprite, Offset(ex - 4*px, e.y), px, e.color);
        }
     }
  }

  @override
  bool shouldRepaint(_SpaceShootersPainter old) => true;
}

class _SpaceGameState {
  double lastTime = 0.0;
  
  double playerX = 0;
  double playerVelocity = 0;
  double playerTargetX = 0;
  double nextMoveTime = 0;
  double formationX = 0;
  
  List<_GameBullet> bullets = [];
  List<_GameEnemy> enemies = [];
  
  double shootTimer = 0;

  void reset(Size size) {
     playerX = size.width / 2;
     playerTargetX = playerX;
     bullets.clear();
     enemies.clear();
     
     // Init Enemies Grid with larger sizing
     double px = 18.0;
     double spacingX = px * 14; 
     double spacingY = px * 10;
     
     int cols = ((size.width * 0.9) / spacingX).floor();
     if (cols < 3) cols = 3;
     if (cols > 7) cols = 7; // Up to 7
     
     double startX = (size.width - (cols * spacingX)) / 2 + (spacingX / 2);
     
     for (int r=0; r<3; r++) { // 3 rows
        for (int c=0; c<cols; c++) {
           enemies.add(_GameEnemy(
              x: startX + c * spacingX,
              y: 50.0 + r * spacingY,
              type: r % 2,
              color: r == 0 ? Colors.purpleAccent : (r == 1 ? Colors.redAccent : Colors.orangeAccent),
              row: r, col: c
           ));
        }
     }
  }

  void update(double time, double speed, Size size) {
     double dt = time - lastTime;
     // Check for reset (negative time or large jump)
     if (dt < 0 || dt > 1.0) { 
        reset(size);
        lastTime = time;
        return;
     }
     lastTime = time;
     
     // 1. Initial Setup
     if (enemies.isEmpty && time < 1.0) reset(size);
     if (playerX == 0) playerX = size.width / 2;

     // 2. AI Player Logic
     // Find target: Lowest row (highest Y), closest to center?
     // Actually, just find the "most threatening" or "easiest to hit"
     // Strategies:
     // - Iterate all active enemies
     // - Prioritize lowest rows (higher Y)
     // - If multiple in same row, pick closest X
     
     _GameEnemy? target;
     double maxRow = -1;
     double minDist = 1e9;
     
     double currentFormationX = sin(time * speed * 0.5) * 50.0; // Predict/Use current
     // Note: we update formationX later in the loop (step 5), but we need it now for targeting.
     // It's a sine wave, smooth.
     
     for (var e in enemies) {
        if (!e.active || e.exploding) continue;
        
        bool better = false;
        if (e.row > maxRow) {
           maxRow = e.row.toDouble();
           minDist = (e.x + currentFormationX - playerX).abs();
           target = e;
        } else if (e.row == maxRow) {
           double dist = (e.x + currentFormationX - playerX).abs();
           if (dist < minDist) {
              minDist = dist;
              target = e;
           }
        }
     }
     
     if (target != null) {
        playerTargetX = target.x + currentFormationX;
     } else {
        // center if no enemies (waiting for respawn)
        playerTargetX = size.width / 2;
     }

     // Smooth Physics Movement (Spring-Damper)
     // Removes oscillation by adding inertia and damping.
     double dist = playerTargetX - playerX;
     
     // Spring stiffness (Controls acceleration speed)
     double k = 15.0; 
     // Damping factor (Controls how fast it settles, 0.0 - 1.0)
     double damping = 0.92;
     
     // F = kx
     double accel = dist * k;
     
     // Integrate
     playerVelocity += accel * dt;
     playerVelocity *= damping; // Apply friction
     
     playerX += playerVelocity * dt;
     
     
     // 3. Shooting (Smart Trigger)
     shootTimer += dt * speed;
     bool aligned = target != null && (playerX - (target.x + currentFormationX)).abs() < 40; // 40px tolerance
     
     if (shootTimer > 0.3 && aligned) { 
        shootTimer = 0;
        // px=18 for shooter. Height=144. ShipY = size.height - 154 (approx).
        bullets.add(_GameBullet(playerX, size.height - 150));
     } else if (shootTimer > 1.5) {
        // Suppression fire if waiting too long
        shootTimer = 0;
        bullets.add(_GameBullet(playerX, size.height - 150));
     }
     
     // 4. Update Bullets
     double bulletSpeed = size.height * 0.8;
     for (int i=bullets.length-1; i>=0; i--) {
        bullets[i].dy -= bulletSpeed * dt * speed; 
        if (bullets[i].dy < -50) {
           bullets.removeAt(i);
        }
     }
     
     // 5. Update Enemies
     formationX = sin(time * speed * 0.5) * 50.0;
     bool altFrame = (time * speed * 4).toInt().isOdd;
     
     for (var e in enemies) {
        if (!e.active) {
           if (time > e.respawnTime) {
              e.active = true;
              e.exploding = false;
           }
           continue;
        }
        
        if (e.exploding) {
           if (time > e.respawnTime - 2.5) { // explosion active for 0.5s
               e.active = false; 
           }
           continue;
        }
        
        e.frame = altFrame ? 1 : 0;
        
        // Collision
        double px = 18.0;
        double ex = e.x + formationX;
        Rect enemyRect = Rect.fromLTWH(ex - 4.5*px, e.y, 9*px, 8*px);
        
        for (int b=bullets.length-1; b>=0; b--) {
           if (enemyRect.contains(Offset(bullets[b].dx, bullets[b].dy))) {
              // Hit!
              e.exploding = true;
              e.respawnTime = time + 3.0; // Wait 3s before returning
              bullets.removeAt(b);
              break;
           }
        }
     }
  }
}

class _GameBullet {
  double dx;
  double dy;
  _GameBullet(this.dx, this.dy);
}

class _GameEnemy {
  double x, y; 
  int type;
  Color color;
  int row, col;
  
  bool active = true;
  bool exploding = false;
  double respawnTime = 0;
  int frame = 0;

  _GameEnemy({required this.x, required this.y, required this.type, required this.color, required this.row, required this.col});
}

// --- TETRIS PAINTER ---
class _TetrisPainter extends CustomPainter {
  final double time;
  final double speed;
  final double transparent;

  _TetrisPainter(this.time, this.speed, this.transparent);
  
  static final _TetrisGameState _gameState = _TetrisGameState();
  
  static const List<Color> _tetrisColors = [
     Color(0xFF00FFFF), // I - Cyan
     Color(0xFFFFFF00), // O - Yellow
     Color(0xFF800080), // T - Purple
     Color(0xFF00FF00), // S - Green
     Color(0xFFFF0000), // Z - Red
     Color(0xFF0000FF), // J - Blue
     Color(0xFFFF7F00), // L - Orange
  ];
  
  static const List<List<Point<int>>> _shapes = [
     [Point(0,1), Point(1,1), Point(2,1), Point(3,1)], // I
     [Point(1,0), Point(2,0), Point(1,1), Point(2,1)], // O
     [Point(1,0), Point(0,1), Point(1,1), Point(2,1)], // T
     [Point(1,0), Point(2,0), Point(0,1), Point(1,1)], // S
     [Point(0,0), Point(1,0), Point(1,1), Point(2,1)], // Z
     [Point(0,0), Point(0,1), Point(1,1), Point(2,1)], // J
     [Point(2,0), Point(0,1), Point(1,1), Point(2,1)], // L
  ];

  @override
  void paint(Canvas canvas, Size size) {
     // Trigger Update
     _gameState.update(time, speed);
     
     // Background
     if (transparent < 0.5) {
        canvas.drawColor(Color(0xFF101010), BlendMode.src);
     }
     
     // Grid Specs
     int cols = _TetrisGameState.cols;
     int rows = _TetrisGameState.rows;
     double blockSize = (size.width / cols);
     
     double boardW = blockSize * cols;
     double boardH = blockSize * rows;
     
     // Scale down if too tall
     if (boardH > size.height) {
        blockSize = size.height / rows;
        boardW = blockSize * cols;
        boardH = blockSize * rows;
     }

     double offsetX = (size.width - boardW) / 2;
     double offsetY = (size.height - boardH) / 2;
     
     // Draw Bucket (Visible Walls)
     final wallPaint = Paint()..color = Colors.white.withOpacity(0.6) ..style = PaintingStyle.stroke ..strokeWidth = 4.0;
     canvas.drawRect(Rect.fromLTWH(offsetX - 2, offsetY - 2, boardW + 4, boardH + 4), wallPaint); 
     
     // Draw Grid (Subtle)
     final gridPaint = Paint()..color = Colors.white10 ..strokeWidth = 1.0;
     for(int c=1; c<cols; c++) canvas.drawLine(Offset(offsetX + c*blockSize, offsetY), Offset(offsetX + c*blockSize, offsetY+boardH), gridPaint);
     for(int r=1; r<rows; r++) canvas.drawLine(Offset(offsetX, offsetY + r*blockSize), Offset(offsetX+boardW, offsetY + r*blockSize), gridPaint);
     
     // Helper
     void drawBlock(int c, int r, Color color) {
        double bx = offsetX + c*blockSize;
        double by = offsetY + r*blockSize;
        double bs = blockSize;
        
        final p = Paint()..color = color;
        canvas.drawRect(Rect.fromLTWH(bx, by, bs, bs), p);
        
        // Bevels
        canvas.drawRect(Rect.fromLTWH(bx, by, bs, bs/8), Paint()..color = Colors.white30);
        canvas.drawRect(Rect.fromLTWH(bx, by, bs/8, bs), Paint()..color = Colors.white30);
        canvas.drawRect(Rect.fromLTWH(bx, by+bs-bs/8, bs, bs/8), Paint()..color = Colors.black26);
        canvas.drawRect(Rect.fromLTWH(bx+bs-bs/8, by, bs/8, bs), Paint()..color = Colors.black26);
     }

     // Draw Stack
     for (int r=0; r<rows; r++) {
        for (int c=0; c<cols; c++) {
           Color? color = _gameState.grid[r * cols + c];
           if (color != null) {
              drawBlock(c, r, color);
           }
        }
     }
     
     // Draw Active Piece
     if (_gameState.activeShape.isNotEmpty) {
        for (var pt in _gameState.activeShape) {
           int x = _gameState.activeX + pt.x;
           int y = _gameState.activeY + pt.y;
           // Clipped top?
           if (y >= 0 && y < rows && x >= 0 && x < cols) {
              drawBlock(x, y, _gameState.activeColor);
           }
        }
     }
  }

  @override
  bool shouldRepaint(_TetrisPainter old) => true;
}

class _TetrisGameState {
  static const int cols = 10;
  static const int rows = 20;
  List<Color?> grid = List.filled(cols * rows, null);
  
  double lastTime = 0.0;
  double dropTimer = 0.0;
  double moveTimer = 0.0;
  
  // Active Piece
  List<Point<int>> activeShape = [];
  Color activeColor = Colors.white;
  int activeX = 0;
  int activeY = 0;
  int currentRotation = 0; // 0,1,2,3
  
  // AI Targets
  int targetX = 0; 
  int targetRotation = 0;
  
  // Helper to rotate point around 0,0
  Point<int> rotatePoint(Point<int> p) => Point(-p.y, p.x);
  
  List<Point<int>> getRotatedShape(List<Point<int>> shape, int rotations) {
     List<Point<int>> res = List.from(shape);
     for(int i=0; i<rotations; i++) {
        res = res.map((p) => Point(-p.y, p.x)).toList();
     }
     return res;
  }

  bool checkCollision(int tx, int ty, List<Point<int>> shape) {
     for (var p in shape) {
        int x = tx + p.x;
        int y = ty + p.y;
        if (x < 0 || x >= cols) return true; 
        if (y >= rows) return true; 
        if (y >= 0 && grid[y * cols + x] != null) return true; 
     }
     return false;
  }
  
  void reset() {
     grid.fillRange(0, grid.length, null);
     activeShape = [];
  }
  
  // --- AI LOGIC ---
  void _findBestMove() {
     double bestScore = -1e9;
     int bestR = 0;
     int bestX = 0;
     
     // 1. Try all rotations
     for(int r=0; r<4; r++) {
        List<Point<int>> testShape = getRotatedShape(activeShape, r); 
        
        // 2. Try all columns
        // Determine width of shape to clamp loop
        int minX = 0, maxX = 0;
        for(var p in testShape) {
           if(p.x < minX) minX = p.x;
           if(p.x > maxX) maxX = p.x;
        }
        
        for(int x = -minX; x < cols - maxX; x++) {
           if (checkCollision(x, activeY, testShape)) continue;
           
           // 3. Drop it hard
           // We can optimize this by finding the highest collision point in the column(s)
           // But naive loop is fine for 10x20
           int y = activeY;
           while(!checkCollision(x, y+1, testShape)) {
              y++;
           }
           
           // 4. Rate the state
           double score = _evaluateGrid(x, y, testShape);
           
           if (score > bestScore) {
              bestScore = score;
              bestR = r;
              bestX = x;
           }
        }
     }
     
     // If we found nothing valid (shouldn't happen on spawn usually), default to current
     bestX = (bestScore == -1e9) ? activeX : bestX;
     
     targetX = bestX;
     targetRotation = bestR;
  }
  
  double _evaluateGrid(int px, int py, List<Point<int>> shape) {
     // Create temp grid logic (virtual)
     // We don't clone the whole grid array for speed, we just peek.
     
     // Heuristics
     int aggregateHeight = 0;
     int holes = 0;
     int bumpiness = 0;
     int completeLines = 0;
     
     // Determine column heights with the new piece
     List<int> colHeights = List.filled(cols, 0);
     
     // Fill colHeights from base grid
     for(int c=0; c<cols; c++) {
        for(int r=0; r<rows; r++) {
           if (grid[r*cols+c] != null) {
              colHeights[c] = rows - r;
              break;
           }
        }
     }
     
     // Update with piece
     for(var p in shape) {
        int x = px + p.x;
        int y = py + p.y;
        if (y>=0 && y<rows && x>=0 && x<cols) {
           int h = rows - y;
           if (h > colHeights[x]) colHeights[x] = h;
        }
     }
     
     for(int h in colHeights) aggregateHeight += h;
     
     // Bumpiness
     for(int c=0; c<cols-1; c++) {
        bumpiness += (colHeights[c] - colHeights[c+1]).abs();
     }
     
     // Holes & Lines requires slightly more complex look
     // Let's approximate lines by filling a virtual grid? 
     // For performance in Dart (Flutter web/mobile), cloning 200 ints is cheap.
     List<bool> occupied = List.filled(cols*rows, false);
     for(int i=0; i<grid.length; i++) occupied[i] = (grid[i] != null);
     
     for(var p in shape) {
        int x = px + p.x;
        int y = py + p.y;
        if (y>=0 && y<rows && x>=0 && x<cols) occupied[y*cols+x] = true;
     }
     
     // Count holes: Empty cell with a filled cell somewhere above it
     for(int c=0; c<cols; c++) {
        bool hitTop = false;
        for(int r=0; r<rows; r++) {
           if (occupied[r*cols+c]) hitTop = true;
           else if (hitTop) holes++;
        }
     }
     
     // Count lines
     for(int r=0; r<rows; r++) {
        bool full = true;
        for(int c=0; c<cols; c++) if (!occupied[r*cols+c]) { full=false; break; }
        if (full) completeLines++;
     }
     
     // Heuristic Weights
     return (-0.6 * aggregateHeight) + (0.8 * completeLines) + (-0.5 * holes) + (-0.2 * bumpiness);
  }

  void spawnPiece() {
     final rng = Random();
     int type = rng.nextInt(_TetrisPainter._shapes.length);
     activeShape = List.from(_TetrisPainter._shapes[type]);
     activeColor = _TetrisPainter._tetrisColors[type];
     
     activeX = cols ~/ 2 - 2;
     activeY = -2; 
     currentRotation = 0;
     
     // Calculate AI Move
     _findBestMove();
     
     if (checkCollision(activeX, 0, activeShape)) {
         reset();
     }
  }

  void lockPiece() {
     for (var p in activeShape) {
        int x = activeX + p.x;
        int y = activeY + p.y;
        if (y < 0) { // Top out
           reset();
           return;
        }
        if (y >= 0 && y < rows && x >= 0 && x < cols) {
           grid[y * cols + x] = activeColor;
        }
     }
     
     // Clear Lines
     for (int r = rows - 1; r >= 0; r--) {
        bool full = true;
        for (int c = 0; c < cols; c++) {
           if (grid[r * cols + c] == null) {
              full = false;
              break;
           }
        }
        if (full) {
           for (int rr = r; rr > 0; rr--) {
              for (int c = 0; c < cols; c++) {
                 grid[rr * cols + c] = grid[(rr - 1) * cols + c];
              }
           }
           for (int c = 0; c < cols; c++) grid[c] = null;
           r++; 
        }
     }
     activeShape = [];
  }

  void update(double time, double speed) {
     double dt = time - lastTime;
     if (dt < 0 || dt > 1.0) {
        lastTime = time;
        return; 
     }
     lastTime = time;
     
     if (activeShape.isEmpty) {
        spawnPiece();
     }
     
     moveTimer += dt * speed;
     double moveInterval = 0.05; // Fast movement to target
     
     if (moveTimer > moveInterval) {
        moveTimer = 0;
        
        // 1. Rotate?
        if (currentRotation != targetRotation) {
           List<Point<int>> newShape = activeShape.map((p) => rotatePoint(p)).toList();
           // Try rotate
           if (!checkCollision(activeX, activeY, newShape)) {
              activeShape = newShape;
              currentRotation = (currentRotation + 1) % 4;
           } else {
              // Wall kick simple (try left/right)
               if (!checkCollision(activeX-1, activeY, newShape)) { activeX--; activeShape=newShape; currentRotation=(currentRotation+1)%4;}
               else if (!checkCollision(activeX+1, activeY, newShape)) { activeX++; activeShape=newShape; currentRotation=(currentRotation+1)%4;}
           }
        } 
        // 2. Move X?
        // Prioritize rotation first (above), then move.
        // We do one step per frame to look "played".
        else if (activeX < targetX) {
           if (!checkCollision(activeX + 1, activeY, activeShape)) activeX++;
        } else if (activeX > targetX) {
           if (!checkCollision(activeX - 1, activeY, activeShape)) activeX--;
        }
     }

     // Gravity
     dropTimer += dt * speed;
     
     // If we are at target X and R, drop fast?
     bool positioned = (activeX == targetX && currentRotation == targetRotation);
     double currentDropInterval = positioned ? 0.05 : 0.4; 
     
     if (dropTimer > currentDropInterval) {
        dropTimer = 0;
        if (!checkCollision(activeX, activeY + 1, activeShape)) {
           activeY++;
        } else {
           lockPiece();
        }
     }
  }
}

// --- ALCHEMY PAINTER ---
class _AlchemyPainter extends CustomPainter {
  final double time;
  final double speed;
  final double turbulence;

  _AlchemyPainter(this.time, this.speed, this.turbulence);

  // Simple pseudo-noise approximation
  double _noise(double x, double y) {
     return sin(x) + cos(y) + sin(x * 0.5 + y * 0.5) * 0.5;
  }

  // Domain Warping fbm
  double _fbm(double x, double y, double t) {
     double v = 0.0;
     double a = 0.5;
     
     // Rotate domain 
     double c = cos(1.0), s = sin(1.0);
     
     for(int i=0; i<3; i++) {
        v += a * sin(x * 2.0 + t + cos(y*1.5));
        
        // Rotate
        double nx = x * c - y * s;
        double ny = x * s + y * c;
        x = nx + 1.0; y = ny + 2.0;
        
        a *= 0.5;
     }
     return v;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Fill Black Base
    canvas.drawColor(Colors.black, BlendMode.src);
    
    // We'll render a lower-res grid for performance then upscale?
    // Actually, for "Canvas" painting, we can't easily do per-pixel shader logic.
    // Instead, we will draw overlapping shapes/gradients to simulate the mixing.
    // OR we create an image buffer. But that's slow.
    // Better approach for Canvas: Draw many large, soft blobs with the warps applied to their positions.

    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40); // High blur for liquid mix

    // Palette
    final colors = [
       const Color(0xFF000000), // Black
       const Color(0xFF1A1A2E), // Deep Ink
       const Color(0xFF4A0E4E), // Purple Ink
       const Color(0xFFB8860B), // Dark Gold
       const Color(0xFFFFD700), // Bright Gold
    ];

    double t = time * speed * 0.2;
    int density = (size.width / 30).toInt(); // Optimization
    
    // Draw "Cells"
    for(int i=0; i<density; i++) {
       double px = (i / density) * size.width;
       double py = (sin(i*0.5 + t) * 0.5 + 0.5) * size.height;
       
       // Domain Warp Position
       double warp = _fbm(px * 0.01, py * 0.01, t);
       double nx = px + warp * 200 * turbulence;
       double ny = py + warp * 200 * turbulence;
       
       // Color Selection based on warp
       int cIdx = ((warp.abs() * 5).toInt() + i) % colors.length;
       paint.color = colors[cIdx].withOpacity(0.5);
       
       // Dynamic Size
       double r = 40.0 + 60.0 * sin(i + t);
       
       canvas.drawCircle(Offset(nx, ny), r, paint);
    }
    
    // Overlay "Gold Dust" (Small sharp specs)
    final dustPaint = Paint()..color = const Color(0xFFFFD700);
    for(int i=0; i<30; i++) {
       double dx = (sin(i*13.0)*0.5+0.5) * size.width;
       double dy = (cos(i*7.0 + t)*0.5+0.5) * size.height;
       
       // Warp dust too
       double warp = _fbm(dx*0.02, dy*0.02, t);
       dx += warp * 100;
       
       canvas.drawCircle(Offset(dx, dy), 1.5, dustPaint);
    }
  }
  
  @override
  bool shouldRepaint(_AlchemyPainter old) => true;
}

// --- GOLDEN SMOKE ECHO PAINTER ---
class _GoldenSmokePainter extends CustomPainter {
  final double time;
  final double speed;
  final double echoDelay;
  final double brightness;
  final double density;
  final int bgColor;
  final double transparent;

  _GoldenSmokePainter(this.time, this.speed, this.echoDelay, this.brightness, this.density, this.bgColor, this.transparent);

  @override
  void paint(Canvas canvas, Size size) {
    // Dark Room Background
    if (transparent < 0.5) {
       canvas.drawColor(Color(bgColor), BlendMode.src);
    }
    
    // 1. Calculate SIMULATED Guest Position
    // Walking left to right every 10 seconds
    double loopT = time % 10.0;
    double guestX = (loopT / 10.0) * size.width;
    double guestY = size.height * 0.5 + sin(time) * 50; // Slight bob
    
    // 2. Calculate ECHO Position (Time - delay)
    // We effectively just look at where the guest WAS.
    double delayedT = (time - echoDelay);
    double echoLoopT = delayedT % 10.0;
    // Handle wrap-around logic roughly or just let it cut
    double echoX = (echoLoopT / 10.0) * size.width;
    double echoY = size.height * 0.5 + sin(delayedT) * 50;
    
    bool echoActive = delayedT > 0;

    final silkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw Smoke Ribbons
    // We draw many lines that form a surface
    int ribbons = (30 * density).toInt();
    for(int i=0; i<ribbons; i++) {
       Path path = Path();
       double yBase = (i / ribbons) * size.height;
       
       path.moveTo(0, yBase);
       
       for(double x = 0; x <= size.width; x+= 20) {
          double n = sin(x * 0.01 + time * speed + i * 0.2);
          double y = yBase + n * 30;
          
          // Apply ECHO Turbulence
          if (echoActive) {
             double dist = sqrt(pow(x - echoX, 2) + pow(y - echoY, 2));
             if (dist < 200) {
                // Swirl force
                double force = (1.0 - dist/200);
                // Twist
                y += sin(dist * 0.1 - time * 5) * 50 * force;
             }
          }
          
          path.lineTo(x, y);
       }
       
       // Vary color slightly for depth, using BRIGHTNESS mod
       if (i % 3 == 0) {
         silkPaint.color = const Color(0xFFD4AF37).withOpacity((0.15 * brightness).clamp(0.0, 1.0)); // Metallic Gold
       } else {
         silkPaint.color = const Color(0xFFF5E6C4).withOpacity((0.1 * brightness).clamp(0.0, 1.0)); // Champagne
       }
       
       canvas.drawPath(path, silkPaint);
    }
  }

  @override
  bool shouldRepaint(_GoldenSmokePainter old) => true;
}

class _BioluminescencePainter extends CustomPainter {
  final double time;
  final double speed;
  final double count;
  final double pulseSpeed;
  _BioluminescencePainter(this.time, this.speed, this.count, this.pulseSpeed);
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(_BioluminescencePainter old) => false;
}

class _MatrixPainter extends CustomPainter {
  final double time;
  final double speed;
  final double scale;
  final double transparent;
  
  _MatrixPainter(this.time, this.speed, this.scale, this.transparent);
  
  // Katakana-like glyphs (Alien look)
  static const String _chars = "ァアィイゥウェエォオカガキギクグケゲコゴサザシジスズセゼソゾタダチヂッツヅテデトドナニヌネノハバパヒビピフブプヘベペホボポマミムメモャヤュユョヨラリルレロヮワヰヱヲンヴヵヶ";
  
  @override
  void paint(Canvas canvas, Size size) {
    // 1. Black Bg (if not transparent)
    if (transparent < 0.5) {
       canvas.drawColor(Colors.black, BlendMode.src);
    }
    
    // 2. Setup Grid
    // Scale 1.0 = 20px font
    double fontSize = 20.0 * scale;
    if (fontSize < 8) fontSize = 8;
    
    int cols = (size.width / fontSize).ceil();
    // We don't restrict rows anymore, we draw continuous streams
    
    final textStyleGreen = TextStyle(
      color: const Color(0xFF00FF00), 
      fontSize: fontSize, 
      fontFamily: 'Roboto', 
      height: 1.0,
      fontWeight: FontWeight.bold
    );
    
    final textStyleWhite = textStyleGreen.copyWith(color: Colors.white, shadows: [
      const Shadow(color: Colors.white, blurRadius: 4)
    ]);
    
    // 3. Draw Columns as Falling Streams
    for (int col = 0; col < cols; col++) {
       // Deterministic random per column
       final r = Random(col + 31337);
       
       // Speed variance
       double colSpeed = speed * (0.8 + 0.4 * r.nextDouble());
       
       // Trail Length
       double trailLen = 10.0 + r.nextInt(15);
       
       // Pixel Position of the Head
       // Loop over height + tail height (in pixels)
       double loopH = size.height + trailLen * fontSize + 100; // Extra buffer
       
       // Smooth pixel movement (time * speed * pixels_per_sec)
       // Base speed 1.0 = 100 pixels/sec?
       double pixelY = (time * 100.0 * colSpeed + r.nextDouble() * 500.0) % loopH;
       
       // Adjust for "off screen" visual
       // pixelY starts at 0..loopH.
       // We want 0 to be top.
       // The "Head" is at pixelY.
       // We draw backward (up) from pixelY.
       
       // If pixelY is > loopH, it wraps to 0.
       // We shift it so that it starts falling from above screen (-trailLen * fontSize)
       double headY = pixelY - (trailLen * fontSize);
       
       // Draw the trail
       int charCount = trailLen.toInt();
       for (int i = 0; i < charCount; i++) {
          double charY = headY - i * fontSize;
          
          // Optimization: Culling
          if (charY > size.height) continue;
          if (charY + fontSize < 0) continue; // Above screen
          
          // Character Selection
          String char;
          if (i == 0) {
             // HEAD: Update fast (Flip)
             // Use time to make it change
             char = _chars[Random(col * 100 + i + (time * 15.0).floor()).nextInt(_chars.length)];
             
             final tp = TextPainter(
               text: TextSpan(text: char, style: textStyleWhite),
               textDirection: TextDirection.ltr
             )..layout();
             tp.paint(canvas, Offset(col * fontSize, charY));
          } else {
             // TRAIL: Static relative to the stream (Flows down without changing)
             // We remove 'time' from the seed.
             // We use 'i' (index in trail) so each position in the trail has a unique char.
             // We add a large multiplier to col to ensure columns look different.
             char = _chars[Random(col * 9999 + i).nextInt(_chars.length)];

             double opacity = 1.0 - (i / charCount);
             // Quadratic fade
             opacity = pow(opacity, 1.5).toDouble();
             
             if (opacity > 0.05) {
                final style = textStyleGreen.copyWith(color: const Color(0xFF00FF00).withOpacity(opacity));
                final tp = TextPainter(
                   text: TextSpan(text: char, style: style),
                   textDirection: TextDirection.ltr
                 )..layout();
                tp.paint(canvas, Offset(col * fontSize, charY));
             }
          }
       }
    }
  }

  @override
  bool shouldRepaint(_MatrixPainter old) => true;
}

class _BioGhostsPainter extends CustomPainter {
  final double time;
  final double speed;
  final double count;
  final double trail; // Length of trail
  final int? singleColor; 
  
  _BioGhostsPainter(this.time, this.speed, this.count, this.trail, [this.singleColor]);
  
  static final _BioGhostsState _gameState = _BioGhostsState();

  @override
  void paint(Canvas canvas, Size size) {
     _gameState.update(time, speed, count, trail, size, singleColor);
     
     for (var ghost in _gameState.ghosts) {
        if (ghost.trail.isEmpty) continue;
        
        // Draw Trail (Tapered)
        // We iterate backwards from the head
        int trailLen = ghost.trail.length;
        double baseSize = ghost.baseSize;
        
        for (int i = 0; i < trailLen; i++) {
           // Alpha fades out
           double alpha = 1.0 - (i / trailLen);
           if (alpha <= 0) continue;
           
           // Size tapers: Head is 100%, Tail is 20%
           double sizeFactor = pow(1.0 - (i / trailLen), 2.0).toDouble(); // Quadratic taper for slimmer tail
           double currentSize = baseSize * sizeFactor;
           
           // Opacity function: Head bright, tail transparent
           double opacity = alpha * alpha; 
           
           final paint = Paint()
             ..shader = RadialGradient(
               colors: [ghost.color.withOpacity(opacity), ghost.color.withOpacity(0.0)],
               stops: const [0.3, 1.0],
             ).createShader(Rect.fromCircle(center: ghost.trail[i], radius: currentSize/2));
             
           canvas.drawCircle(ghost.trail[i], currentSize/2, paint);
        }
     }
  }

  @override
  bool shouldRepaint(_BioGhostsPainter old) => true;
}

class _BioGhostsState {
   List<_GhostEntity> ghosts = [];
   double lastTime = 0.0;
   
   void update(double time, double speed, double countParam, double trailParam, Size size, int? singleColor) {
      double dt = time - lastTime;
      // Handle reset or pause
      if (dt < 0 || dt > 1.0) {
         lastTime = time;
         return; 
      }
      lastTime = time;
      
      int targetCount = countParam.toInt();
      
      // Manage Population
      if (ghosts.length < targetCount) {
         int toAdd = targetCount - ghosts.length;
         for(int i=0; i<toAdd; i++) {
            ghosts.add(_GhostEntity(size, singleColor));
         }
      } else if (ghosts.length > targetCount) {
         ghosts.removeRange(targetCount, ghosts.length);
      }
      
      // Update Physics
      for (var g in ghosts) {
         g.update(time, dt, speed, trailParam, size, singleColor);
      }
   }
}

class _GhostEntity {
   Offset pos = Offset.zero;
   Offset vel = Offset.zero;
   List<Offset> trail = [];
   
   Color color = Colors.white;
   double baseSize = 50.0;
   
   // Wander properties
   double angle = 0;
   
   _GhostEntity(Size size, int? singleColor) {
     reset(size, singleColor);
   }
   
   void reset(Size size, int? singleColor) {
      final r = Random();
      pos = Offset(r.nextDouble() * size.width, r.nextDouble() * size.height);
      angle = r.nextDouble() * pi * 2;
      double speed = 50.0 + r.nextDouble() * 150.0; // More speed variance
      vel = Offset(cos(angle)*speed, sin(angle)*speed);
      
      baseSize = 60.0 + r.nextDouble() * 60.0;
      
      if (singleColor != null) {
         color = Color(singleColor);
      } else {
         final colors = [
            const Color(0xAA00FFFF), 
            const Color(0xAA00FFaa), 
            const Color(0xAA00CCFF), 
         ];
        color = colors[r.nextInt(colors.length)];
      }
   }
   
   void update(double time, double dt, double speedParam, double trailLenParam, Size size, int? singleColor) {
      final r = Random();
      
      // 1. Steering (Wander)
      // Change angle slightly each frame
      double turnSpeed = 4.0 * speedParam;
      angle += (r.nextDouble() - 0.5) * dt * turnSpeed;
      
      // Target Velocity
      double baseSpeed = 100.0;
      // Add per-ghost speed variation that changes slowly over time or is seeded
      double speedVar = sin(time * 0.5 + pos.dx * 0.01) * 50.0;
      
      double moveSpeed = (baseSpeed + speedVar) * speedParam;
      if (moveSpeed < 10.0) moveSpeed = 10.0;

      Offset targetVel = Offset(cos(angle)*moveSpeed, sin(angle)*moveSpeed);
      
      // Smooth interpolation for velocity
      double lerp = 2.0 * dt;
      vel = Offset.lerp(vel, targetVel, lerp)!;
      
      // 2. Move
      pos += vel * dt;
      
      // 3. Bounce Walls
      if (pos.dx < 0) { pos = Offset(0, pos.dy); vel = Offset(-vel.dx, vel.dy); angle = pi - angle; }
      if (pos.dx > size.width) { pos = Offset(size.width, pos.dy); vel = Offset(-vel.dx, vel.dy); angle = pi - angle; }
      if (pos.dy < 0) { pos = Offset(pos.dx, 0); vel = Offset(vel.dx, -vel.dy); angle = -angle; }
      if (pos.dy > size.height) { pos = Offset(pos.dx, size.height); vel = Offset(vel.dx, -vel.dy); angle = -angle; }
      
      // 4. Update Trail
      // Add current position to head
      trail.insert(0, pos);
      
      // Trim trail
      // trailParam is "length factor". Let's say 1.0 = 20 points?
      int maxPoints = (trailLenParam * 5).toInt();
      if (maxPoints < 2) maxPoints = 2;
      
      if (trail.length > maxPoints) {
         trail.removeRange(maxPoints, trail.length);
      }
      
      // Update color if param changed (optional, but good for realtime edit)
      if (singleColor != null && color.value != singleColor) {
         color = Color(singleColor);
      }
   }
}

class _RainbowPainter extends CustomPainter {
  final double time;
  final double speed;
  final double scale;
  final double angle; // Degrees
  
  _RainbowPainter(this.time, this.speed, this.scale, this.angle);

  @override
  void paint(Canvas canvas, Size size) {
    // We want the gradient to scroll *along* the angle direction.
    
    // 1. Setup Matrix
    // Convert angle to radians
    double rad = angle * pi / 180.0;
    
    // Calculate scrolling offset
    // The gradient repeats every "cycleW".
    // We scroll X in the gradient's local space.
    double cycleW = size.width / scale;
    if (cycleW <= 0) cycleW = size.width;
    
    double scroll = -(time * 200 * speed) % cycleW;
    
    final matrix = Matrix4.identity()
      ..translate(size.width/2, size.height/2) // To center
      ..rotateZ(rad)
      ..translate(-size.width/2, -size.height/2) // Back
      ..translate(scroll, 0.0); // Scroll in local X (which is now angled globally?)
      
    final gradient = LinearGradient(
      colors: const [
        Colors.red, Colors.orange, Colors.yellow, 
        Colors.green, Colors.cyan, Colors.blue, 
        Colors.purple, Colors.red
      ],
      tileMode: TileMode.repeated,
      transform: _MatrixTransform(matrix),
    );
    
    final Paint paint = Paint()
      ..shader = gradient.createShader(Offset.zero & size);
      
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_RainbowPainter old) => 
    old.time != time || old.angle != angle || old.scale != scale || old.speed != speed;
}

class _RainbowRipplePainter extends CustomPainter {
  final double time;
  final double speed;
  final double scale;
  
  _RainbowRipplePainter(this.time, this.speed, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
     // Radial Gradient expanding outwards
     
     // 1. Calculate Colors for this frame
     // We rotate the hue based on time.
     List<Color> colors = [];
     List<double> stops = [];
     int steps = 360; // Max smoothness (1 degree per step)
     
     // Normalized phase time
     // Slower speed: default speed reduced by half relative to previous
     double tVal = time * speed * 360.0 * 0.5;
     
     for (int i=0; i<=steps; i++) {
        double f = i / steps; // 0..1 radius
        stops.add(f);
        
        // Hue at this radius
        double hue = (f * 360.0 * 2 - tVal) % 360.0; 
        if (hue < 0) hue += 360.0;
        
        colors.add(HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor());
     }
     
     final gradient = RadialGradient(
       colors: colors,
       stops: stops,
       radius: 1.0 / scale, // Scale inversely affects radius size
       tileMode: TileMode.repeated,
     );
     
     final paint = Paint()
       ..shader = gradient.createShader(Offset.zero & size);
       
     canvas.drawRect(Offset.zero & size, paint);
  }
  
  @override
  bool shouldRepaint(_RainbowRipplePainter old) => true;
}

// Helper for arbitary matrix transform in gradients
class _MatrixTransform extends GradientTransform {
  final Matrix4 matrix;
  const _MatrixTransform(this.matrix);
  
  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    return matrix;
  }
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
  final double fontSize;
  final double transparent; // 0.0 to 1.0 (>=0.5 is transparent)
  final String font;
  
  _TextScrollPainter({
    required this.time,
    required this.text,
    required this.bgColor,
    required this.textColor,
    required this.speed,
    required this.fontSize,
    required this.transparent,
    required this.font,
  });

  @override
  void paint(Canvas canvas, Size size) {
     if (transparent < 0.5) {
        canvas.drawColor(Color(bgColor), BlendMode.src);
     }
     
     TextPainter tp = TextPainter(
       text: TextSpan(
         text: text, 
         style: TextStyle(
            color: Color(textColor), 
            fontSize: fontSize,  // Absolute Sizing (10-100)
            fontWeight: FontWeight.bold,
            fontFamily: font,
         )
       ),
       textDirection: TextDirection.ltr
     );
     tp.layout();
     
     // Scroll Right to Left
     double totalW = tp.width + size.width;
      double x;
      if (speed == 0.0) {
         // Center
         x = (size.width - tp.width) / 2;
      } else {
         double offset = (time * 200 * speed) % totalW;
         x = size.width - offset;
      }
     
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

// NEW EFFECT PAINTERS

class _PacmanPainter extends CustomPainter {
  final double time;
  final double speed;
  final double transparent;

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

  _PacmanPainter(this.time, this.speed, this.transparent);

  @override
  void paint(Canvas canvas, Size size) {
      // Background
      if (transparent < 0.5) {
         canvas.drawColor(Colors.black, BlendMode.src);
      }
      
      // Layout Logic: SQUARE Aspect Ratio
      double mazeH = size.height;
      double mazeW = size.width;
      
      // Grid 15x15 - Use min dimension to ensure square fit
      double cellSize = min(mazeW, mazeH) / 15.0;
      
      double gridW = cellSize * 15;
      double gridH = cellSize * 15;
      
      // Center the square grid
      double offX = (mazeW - gridW) / 2;
      double offY = (mazeH - gridH) / 2;
      
      canvas.translate(offX, offY);
      
      // WALL STYLE
      final wallPaint = Paint()
        ..color = Colors.blueAccent 
        ..style = PaintingStyle.stroke
        ..strokeWidth = cellSize * 0.25 
        ..strokeCap = StrokeCap.round;
        
      final dotPaint = Paint()..color = Colors.white.withOpacity(0.8)..style = PaintingStyle.fill;
      
      // Calculate Path Progress
      List<Point<int>> path = _generatePath();
      double totalDist = path.length.toDouble();
      // Loop smoothly
      double currentDist = (time * speed * 5.0) % totalDist; 
      
      // Interpolate position
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
               // Walls
               canvas.drawRect(r.deflate(cellSize * 0.15), wallPaint);
            } else {
               // Dots
               Point<int> pt = Point(x,y);
               int dotIdx = path.indexOf(pt);
               bool isEaten = false;
               if (dotIdx != -1) {
                  // Eaten logic
                  if (currentDist > dotIdx) isEaten = true;
               }
               if (!isEaten) {
                  canvas.drawCircle(r.center, cellSize * 0.15, dotPaint);
               }
            }
         }
      }
      
      // Characters
      double charSize = cellSize * 0.9;
      
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
     double r = size * 0.5;
     Rect rect = Rect.fromCircle(center: pos, radius: r);
     
     // Head
     canvas.drawArc(rect, pi, pi, true, p);
     // Body
     canvas.drawRect(Rect.fromLTWH(rect.left, rect.center.dy, rect.width, rect.height/2), p);
     
     // Eyes
     final eyeWhite = Paint()..color = Colors.white;
     final eyePupil = Paint()..color = Colors.blue[900]!;
     double er = r * 0.35;
     canvas.drawCircle(pos + Offset(-r*0.3, -r*0.1), er, eyeWhite);
     canvas.drawCircle(pos + Offset(r*0.3, -r*0.1), er, eyeWhite);
     canvas.drawCircle(pos + Offset(-r*0.2, -r*0.1), er/2, eyePupil);
     canvas.drawCircle(pos + Offset(r*0.4, -r*0.1), er/2, eyePupil);
  }

  List<Point<int>> _generatePath() {
     List<Point<int>> p = [];
     
     // Helper to add line segments without duplicating points
     // This ensures linear movement speed constant through corners
     void addLine(int x1, int y1, int x2, int y2) {
        List<Point<int>> seg = _line(x1, y1, x2, y2);
        if (p.isNotEmpty && seg.isNotEmpty && p.last == seg.first) {
           seg.removeAt(0);
        }
        p.addAll(seg);
     }
     
     // 1. Top-Left Loop
     addLine(1,1, 1,5);
     addLine(1,5, 3,5);
     addLine(3,5, 3,3);
     addLine(3,3, 11,3);
     
     // Right Side Logic
     addLine(11,3, 11,5);
     addLine(11,5, 13,5);
     addLine(13,5, 13,1);
     addLine(13,1, 8,1);
     addLine(8,1, 8,3); 
     addLine(8,3, 3,3); // Return to center highway
     
     // Lower Section
     addLine(3,3, 3,11);
     addLine(3,11, 11,11);
     
     // Bottom Right Dip
     addLine(11,11, 11,13);
     addLine(11,13, 13,13);
     addLine(13,13, 13,9);
     addLine(13,9, 13,13); // Backtrack
     addLine(13,13, 11,13);
     addLine(11,13, 11,11);
     
     // Return West
     addLine(11,11, 3,11);
     
     // Bottom Left Dip
     addLine(3,11, 3,13);
     addLine(3,13, 1,13);
     addLine(1,13, 1,9);
     addLine(1,9, 1,13); // Backtrack
     addLine(1,13, 3,13);
     addLine(3,13, 3,11);
     
     // Return North
     addLine(3,11, 3,3);
     
     // Final Leg to Start (Close Loop)
     addLine(3,3, 3,5);
     addLine(3,5, 1,5);
     addLine(1,5, 1,1);
     
     // Clean up loop closure: last point (1,1) == first point (1,1)
     // Use one of them, typically keep first, remove last, so looping wraps p.last -> p[0]
     if (p.isNotEmpty && p.last == p.first) {
        p.removeLast();
     }
     
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

class _ClubShadowsPainter extends CustomPainter {
  final double time;
  final double style; 
  final double count;
  _ClubShadowsPainter(this.time, this.style, this.count);
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(_ClubShadowsPainter old) => false;
}

class _ArrivalPainter extends CustomPainter {
  final double time;
  final double speed;
  final double flow; 
  final double invert;
  final double duration;
  final double maxScale;

  _ArrivalPainter(this.time, this.speed, this.flow, this.invert, this.duration, this.maxScale);
  
  double _noise(double x, double y) {
     return sin(x * 12.9898 + y * 78.233) * 43758.5453 - (sin(x * 12.9898 + y * 78.233) * 43758.5453).floor();
  }

  @override
  void paint(Canvas canvas, Size size) {
     bool isInverted = invert > 0.5;
     Color inkColor = isInverted ? Colors.black : Colors.white;
     Color bgColor = isInverted ? Colors.white : Colors.black;
     
     canvas.drawColor(bgColor, BlendMode.src);
     
     double centerX = size.width / 2;
     double centerY = size.height / 2;
     
     // Dynamics
     double tRatio = (speed - 0.1) / (3.0 - 0.1); 
     double traverseTime = 10.0 - (tRatio * 9.0).clamp(0.0, 9.0);
     if (traverseTime < 0.5) traverseTime = 0.5;
     
     double holdTime = duration * 2.0; 
     double totalLife = traverseTime + holdTime + traverseTime; 
     
     // Force SINGLE dense discharge to match "THE image".
     // If user wants more activity, they can increase Speed, which reduces totalLife.
     // But parallel overlapping dense fractals would kill initial performance.
     int simultaneous = 1;
     double spawnInterval = totalLife; // Strictly one after another (or use flow?)
     
     // Actually, if we want CONTINUOUS light flow, we might need overlapping if the previous one is dissipating.
     // Let's allow overlap only if flow > 2.0.
     if (flow > 2.0) simultaneous = 2;

     spawnInterval = totalLife / simultaneous; // Spacing
     
     for (int i = 0; i < simultaneous * 2; i++) { 
        double currentStep = (time / spawnInterval).floorToDouble();
        double seedIndex = currentStep - i;
        double spawnTime = seedIndex * spawnInterval;
        
        double age = time - spawnTime;
        if (age < 0 || age > totalLife) continue;
        
        _drawDischarge(
          canvas, size, 
          centerX, centerY, 
          seedIndex, age, traverseTime, holdTime, 
          inkColor
        );
     }
  }

  void _drawDischarge(
      Canvas canvas, Size size,
      double cx, double cy,
      double seed, double age, 
      double traverseTime, double holdTime,
      Color baseColor
  ) {
      double reach = size.longestSide * maxScale * 0.6; 
      double velocity = reach / traverseTime;
      
      double headDist = 0.0;
      double tailDist = 0.0;
      
      if (age <= traverseTime) {
         headDist = age * velocity;
      } else if (age <= traverseTime + holdTime) {
         headDist = reach + 2000;
      } else {
         double dAge = age - (traverseTime + holdTime);
         headDist = reach + 2000;
         tailDist = dAge * velocity;
      }

      if (tailDist > reach) return; 

      // Structure Generation
      // To match the image: EXTREMELY DENSE branching.
      // Roots: 20-60 based on flow.
      int roots = (20 + 30 * flow).toInt().clamp(20, 80); 
      
      // Buckets
      Map<double, Path> buckets = {
         5.0: Path(),
         3.0: Path(),
         1.5: Path(),
         0.8: Path(), // Very fine tips
      };
      
      Path getBucket(double t) {
         if (t >= 4.0) return buckets[5.0]!;
         if (t >= 2.0) return buckets[3.0]!;
         if (t >= 1.0) return buckets[1.5]!;
         return buckets[0.8]!;
      }

      // Opacity
      double opacity = 1.0;
      if (age < 0.2) opacity = age / 0.2; // Fast fade in
      
      Paint p = Paint()
        ..color = baseColor.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round 
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 1.5); // Sharp electrical look

      List<_BranchNode> queue = [];
      
      for (int i=0; i<roots; i++) {
        double normalized = i / roots;
        double jitter = (_noise(seed, i.toDouble()) - 0.5) * (2 * pi / roots) * 0.9;
        double angle = normalized * 2 * pi + jitter;
        
        queue.add(_BranchNode(
           x: cx, y: cy, angle: angle, 
           thickness: 7.0, 
           dist: 0, 
           maxDist: reach, depth: 0
        ));
      }
      
      int count = 0; 
      int limit = 4000; // Increased limit for density
      double step = 8.0; // Smaller steps for more jaggy details
      
      while (queue.isNotEmpty && count < limit) {
         _BranchNode node = queue.removeLast();
         if (node.thickness < 0.4) continue; 
         
         double r1 = _noise(node.x + seed, node.y);
         double r2 = _noise(node.y, node.x + seed);
         
         // Curlier?
         double turn = (r1 - 0.5) * 1.5; 
         double nextAngle = node.angle + turn;
         
         double nx = node.x + cos(nextAngle) * step;
         double ny = node.y + sin(nextAngle) * step;
         double distal = node.dist + step;
         
         bool visible = true;
         if (distal < tailDist) visible = false; 
         // Allow generating PAST head (but not drawing) for future frames? 
         // No, this is deterministic per frame. We generate fresh.
         // If we don't generate past head, next frame will start from scratch anyway.
         // Correct.
         
         if (distal > headDist + 100) continue; 
         
         if (visible && distal <= headDist) {
             // Draw
             Path b = getBucket(node.thickness);
             b.moveTo(node.x, node.y);
             b.lineTo(nx, ny);
             count++;
         }
         
         double nextThick = node.thickness * 0.96; // Slower taper
         
         queue.add(_BranchNode(
             x: nx, y: ny, angle: nextAngle, 
             thickness: nextThick, 
             dist: distal, maxDist: node.maxDist, depth: node.depth
         ));
         
         // HIGH split prob for feathery look
         // But only if we have capacity
         double splitProb = 0.20 * flow; 
         if (node.depth < 12 && r2 > (1.0 - splitProb)) {
            double fork = nextAngle + (r2 > 0.9 ? 1.2 : -1.2); // Wide forks
            queue.add(_BranchNode(
                x: nx, y: ny, angle: fork, 
                thickness: nextThick * 0.6, // Side branches thinner
                dist: distal, maxDist: node.maxDist, depth: node.depth + 1
            ));
         }
      }
      
      for (var entry in buckets.entries) {
          if (entry.value.getBounds().isEmpty) continue;
          p.strokeWidth = entry.key;
          canvas.drawPath(entry.value, p);
      }
  }

  @override
  bool shouldRepaint(_ArrivalPainter old) => true;
}

class _BranchNode {
  final double x, y, angle, thickness, dist, maxDist;
  final int depth;
  _BranchNode({
    required this.x, required this.y, required this.angle, 
    required this.thickness, required this.dist, required this.maxDist, 
    required this.depth
  });
}
class _GeometricPainter extends CustomPainter {
  final double time;
  final double speed;
  final double shape; // 0=Line, 1=Rectangle, 2=Triangle, 3=Circle
  final double direction; // 0=Horizontal, 1=Vertical
  final double sizeParam;
  final double spacing;
  final double count;
  final int color;
  final double transparent;

  _GeometricPainter({
    required this.time,
    required this.speed,
    required this.shape,
    required this.direction,
    required this.sizeParam,
    required this.spacing,
    required this.count,
    required this.color,
    required this.transparent,
  });

  @override
  void paint(Canvas canvas, Size size) {
     if (transparent < 0.5) {
        canvas.drawColor(Colors.black, BlendMode.src);
     }
     
     final paint = Paint()..color = Color(color);
     
     // 0=Left, 1=Right, 2=Up, 3=Down
     // isVert only for 2 and 3
     bool isVert = direction > 1.5;
     double activeDim = isVert ? size.height : size.width;
     double crossDim = isVert ? size.width : size.height;
     
     double tVal = (time * speed * 100.0);
     
     if (shape < 0.5) {
        // 0: Lines (Multi)
        int lineCount = count.toInt();
        if (lineCount < 1) lineCount = 1;
        
        for(int i=0; i<lineCount; i++) {
           double pos = (tVal + i * spacing) % activeDim;
           
           // Direction check (Reverse)
           if (direction < 0.5 || (direction > 1.5 && direction < 2.5)) {
              // Left (0) or Up (2) -> Standard for loop?
              // Actually direction mapping: 0=Left, 1=Right, 2=Up, 3=Down
              // If Left or Up, we might want -tVal behavior or strict override.
              // Let's stick to tVal logic:
              // Left/Up -> Reverse visual flow?
              if (direction < 0.5 || (direction > 1.5 && direction < 2.5)) {
                 pos = activeDim - pos;
              }
           }

           if (isVert) {
              // Y is pos
              canvas.drawRect(Rect.fromLTWH(0, pos, crossDim, sizeParam), paint);
              // Wrap visual
              if (pos + sizeParam > activeDim) {
                  canvas.drawRect(Rect.fromLTWH(0, pos - activeDim, crossDim, sizeParam), paint);
              }
              if (pos < 0) { // Wrap reverse
                  canvas.drawRect(Rect.fromLTWH(0, activeDim + pos, crossDim, sizeParam), paint);
              }
           } else {
              // X is pos
              canvas.drawRect(Rect.fromLTWH(pos, 0, sizeParam, crossDim), paint);
              if (pos + sizeParam > activeDim) {
                  canvas.drawRect(Rect.fromLTWH(pos - activeDim, 0, sizeParam, crossDim), paint);
              }
              if (pos < 0) {
                  canvas.drawRect(Rect.fromLTWH(activeDim + pos, 0, sizeParam, crossDim), paint);
              }
           }
        }
     } else {
        // Shapes
        // 1=Rectangle, 2=Triangle, 3=Circle
        int shapeType = shape.round();
        int itemCount = count.toInt();
        Random r = Random(1337);
        
        // Direction Vector
        double dx = 0, dy = 0;
        if (direction < 0.5) { dx = -1; } // Left
        else if (direction < 1.5) { dx = 1; } // Right
        else if (direction < 2.5) { dy = -1; } // Up
        else { dy = 1; } // Down
        
        double moveDist = time * speed * 200.0;

        for(int i=0; i<itemCount; i++) {
           double track = r.nextDouble() * crossDim;
           double speedVar = 0.5 + r.nextDouble();
           double sizeVar = 0.5 + r.nextDouble();
           
           double mySize = sizeParam * sizeVar;
           double myW = mySize;
           double myH = mySize;
           
           if (shapeType == 1) { // Rectangle
              // Random aspect ratio
              if (r.nextBool()) myW *= 1.5; else myH *= 1.5;
           }
           
           double myPos = (moveDist * speedVar + r.nextDouble() * activeDim) % (activeDim + mySize*2);
           myPos -= mySize; 
           
           if (dx < 0 || dy < 0) myPos = activeDim - myPos - mySize;

           double cx, cy;
           if (isVert) {
              cx = track;
              cy = myPos;
           } else {
              cx = myPos;
              cy = track;
           }
           
           if (shapeType == 1) {
              // Rect
              canvas.drawRect(Rect.fromLTWH(cx, cy, myW, myH), paint);
           } else if (shapeType == 2) {
              // Triangle
              Path path = Path();
              if (isVert) {
                 path.moveTo(cx + myW/2, cy);
                 path.lineTo(cx + myW, cy + myH);
                 path.lineTo(cx, cy + myH);
              } else {
                 path.moveTo(cx + myW, cy + myH/2);
                 path.lineTo(cx, cy);
                 path.lineTo(cx, cy + myH);
              }
              path.close();
              canvas.drawPath(path, paint);
           } else {
              // Circle
              canvas.drawCircle(Offset(cx + myW/2, cy + myH/2), myW/2, paint);
           }
        }
     }
  }

  @override
  bool shouldRepaint(_GeometricPainter old) => true;
}
