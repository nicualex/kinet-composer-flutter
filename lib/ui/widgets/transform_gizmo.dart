import 'dart:math';

import 'package:flutter/material.dart';
import '../../models/show_manifest.dart';
import '../../models/media_transform.dart';

// Enum shared with Gizmo
enum EditMode { zoom, crop }

class TransformGizmo extends StatefulWidget {
  final MediaTransform transform;
  final bool isCropMode;
  final bool lockAspect;
  final EditMode editMode; // NEW
  final Function(MediaTransform) onUpdate;
  final VoidCallback? onDoubleTap; // NEW
  final Widget child;
  final bool isSelected; // NEW

  const TransformGizmo({
    super.key,
    required this.transform,
    required this.onUpdate,
    required this.child,
    this.onDoubleTap,
    this.isCropMode = false,
    this.lockAspect = true,
    this.editMode = EditMode.zoom, // Default
    this.isSelected = true,
    this.showOutline = true, // NEW
    this.contentSize, // Optional Override
  });

  final Size? contentSize;
  final bool showOutline;

  @override
  State<TransformGizmo> createState() => _TransformGizmoState();
}

class _TransformGizmoState extends State<TransformGizmo> {
  // Drag state
  Offset? _dragStart;
  MediaTransform? _initialTransform;
  final GlobalKey _contentKey = GlobalKey(); // Track content size

  // For rotation


  void _onPanStart(DragStartDetails details) {
    _dragStart = details.globalPosition;
    _initialTransform = widget.transform; 
  }

  // Helper to determine the ACTUAL screen scale ratio (Screen px per Local px)
  // This accounts for FittedBox, Transform, DevicePixelRatio, etc.
  double _getGlobalScaleFactor() {
      final RenderBox? box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return 1.0;
      
      // Measure 100 local pixels in global space
      final p1 = box.localToGlobal(Offset.zero);
      final p2 = box.localToGlobal(const Offset(100, 0));
      final dist = (p2 - p1).distance;
      
      // GlobalScale = GlobalDist / LocalDist
      if (dist == 0) return 1.0;
      return dist / 100.0;
  }

  void _onTranslateUpdate(DragUpdateDetails details) {
     if (_initialTransform == null) return;
     
     // CROP MODE: Pan moves the CROP RECT
     if (widget.isCropMode && widget.editMode == EditMode.crop && widget.transform.crop != null) {
       Size size = const Size(100, 100);
       if (_contentKey.currentContext != null) {
          final box = _contentKey.currentContext!.findRenderObject() as RenderBox;
          size = box.size;
       }
       
       // CORRECT PROPORTIONALITY:
       // The 'size' we get is the Intrinsic (Content) Size.
       // The screen distance we drag is transformed by Scale.
       // So we must divide delta by Scale to get "Content Factor".
       
       double sX = _initialTransform!.scaleX;
       double sY = _initialTransform!.scaleY;
       if (sX == 0) sX = 1; 
       if (sY == 0) sY = 1;

       // Use local delta (unrotated) or global?
       // Crop Rect is defined in Content Local Space.
       // If rotation exists, Global Delta X does not align with Content X.
       // We MUST un-rotate Global Delta first.
       
       Offset globalDelta = details.globalPosition - _dragStart!;
       
       double rotRad = -_initialTransform!.rotation * pi / 180.0;
       double dx_local_px = globalDelta.dx * cos(rotRad) - globalDelta.dy * sin(rotRad);
       double dy_local_px = globalDelta.dx * sin(rotRad) + globalDelta.dy * cos(rotRad);
       
       // Now normalize by Scale to get "Content Pixels" delta
       double dx_content = dx_local_px / sX;
       double dy_content = dy_local_px / sY;

       double dxPct = (dx_content / size.width) * 100;
       double dyPct = (dy_content / size.height) * 100;
       
       final initialCrop = _initialTransform!.crop!;
       
       double newX = initialCrop.x + dxPct;
       double newY = initialCrop.y + dyPct;

       widget.onUpdate(MediaTransform(
         scaleX: _initialTransform!.scaleX,
         scaleY: _initialTransform!.scaleY,
         translateX: _initialTransform!.translateX,
         translateY: _initialTransform!.translateY,
         rotation: _initialTransform!.rotation,
         crop: CropInfo(
           x: newX,
           y: newY,
           width: initialCrop.width,
           height: initialCrop.height
         ),
       ));
       return;
     }

     // NORMAL MODE: Pan moves the OBJECT
     // We must correct for the Global View Scale (FittedBox, etc.)
     // If the view is zoomed out (Scale < 1), 1 screen pixel = Many logic pixels.
     double globalScale = _getGlobalScaleFactor();
     if (globalScale == 0) globalScale = 1.0;

     double dx = (details.globalPosition.dx - _dragStart!.dx) / globalScale;
     double dy = (details.globalPosition.dy - _dragStart!.dy) / globalScale;
     
     widget.onUpdate(MediaTransform(
       scaleX: _initialTransform!.scaleX,
       scaleY: _initialTransform!.scaleY,
       translateX: _initialTransform!.translateX + dx,
       translateY: _initialTransform!.translateY + dy,
       rotation: _initialTransform!.rotation,
       crop: _initialTransform!.crop,
     ));
  }


  
  void _onScaleUpdate(DragUpdateDetails details, Alignment handleAlignment) {
      if (widget.isCropMode && widget.editMode == EditMode.crop && widget.transform.crop != null) {
         _onCropHandleUpdate(details, handleAlignment);
         return;
      }
      
      if (_initialTransform == null || _dragStart == null) return;

      // 1. Get Intrinsic Size
      Size intrinsicSize = const Size(100, 100); 
      if (_contentKey.currentContext != null) {
          final box = _contentKey.currentContext!.findRenderObject() as RenderBox;
          intrinsicSize = box.size;
      }

      // 2. Calculate Logic Delta (Un-rotated, Un-scaled Screen Delta)
      // We need accurate screen delta to logic delta conversion
      double globalScale = _getGlobalScaleFactor();
      if (globalScale == 0) globalScale = 1.0;

      Offset globalDelta = details.globalPosition - _dragStart!;
      
      // Rotate Global Delta into Local Space to align with handle axes (Left/Right/Top/Bottom)
      // Note: This rotation is purely to decompose Drag into Width/Height components relative to the object.
      double rotRad = _initialTransform!.rotation * pi / 180.0; 
      // We rotate by NEGATIVE angle to go from Global -> Local axis
      double dx_local_axis = globalDelta.dx * cos(-rotRad) - globalDelta.dy * sin(-rotRad);
      double dy_local_axis = globalDelta.dx * sin(-rotRad) + globalDelta.dy * cos(-rotRad);

      // Convert Screen Pixels -> Logic Pixels
      double logic_dx = dx_local_axis / globalScale;
      double logic_dy = dy_local_axis / globalScale;

      // 3. Determine Scale Changes based on Handle
      // Scale = LogicSize / IntrinsicSize.
      // DeltaScale = LogicDelta / IntrinsicSize.
      
      double dSX = 0.0;
      double dSY = 0.0;

      // X-Axis Logic
      if (handleAlignment.x > 0) { // Right Handle
         dSX = logic_dx / intrinsicSize.width;
      } else if (handleAlignment.x < 0) { // Left Handle
         dSX = -logic_dx / intrinsicSize.width; // Drag Left (-) = Increase Width (+)
      }

      // Y-Axis Logic
      if (handleAlignment.y > 0) { // Bottom Handle
         dSY = logic_dy / intrinsicSize.height;
      } else if (handleAlignment.y < 0) { // Top Handle
         dSY = -logic_dy / intrinsicSize.height; // Drag Up (-) = Increase Height (+)
      }

      double initialSX = _initialTransform!.scaleX;
      double initialSY = _initialTransform!.scaleY;
      
      // Apply Aspect Ratio Lock
      if (widget.lockAspect) {
         // To maximize intuitive feel, take the larger of the two inputs? 
         // Or project onto diagonal?
         // Simplest: Average or Max. Let's use the Component that is actually being pulled.
         // If pulling Corner, typically we want the dominant drag direction.
         // But for simplicity, let's say dS = (dSX + dSY) / 2? Or Max?
         // Better: Use diagonal projection?
         // Current simple approach used previously:
         
         double dS = 0;
         if (handleAlignment.x != 0 && handleAlignment.y != 0) {
             // Corner: Check which dimension is "free-est" or just sum?
             // If I drag Right/Down, both positive.
             // If Aspect Lock, modifying Scaler should trigger proportional ScaleY.
             
             // Let's rely on the handle sign.
             double signX = handleAlignment.x;
             double signY = handleAlignment.y;
             
             // dSX is already corrected for sign. 
             // LogicDelta (10, 10) on BottomRight (1, 1) -> dSX=+, dSY=+
             // LogicDelta (10, 10) on TopLeft (-1, -1) -> dSX=-, dSY=- (Drag Right/Down shrinks)
             
             // If locked: dSX should roughly equal dSY * Aspect?
             // Let's just take the average magnitude change?
             // Or better, just apply dSX to both? 
             
             // User complaint: "Feels like I move mouse more than outline".
             // This suggests scaling factor is too small.
             // If I drag 100px, I expect edge to move 100px.
             // Edge position = Center + (Scale * 0.5 * Width).
             // Delta Edge = Delta Scale * 0.5 * Width.
             // We want Delta Edge = Drag Delta.
             // Drag Delta = Delta Scale * 0.5 * Width.
             // Delta Scale = Drag Delta / (0.5 * Width).
             // Delta Scale = 2 * Drag Delta / Width.
             
             // MY PREVIOUS FORMULA: dScale = Delta / Width.
             // This is off by factor of 2! 
             // Because Pivot is Center, moving one edge 10px grows width by 20px (if symmetric) 
             // OR grows width by 10px but center shifts 5px.
             
             // IF ANCHORED SCALING (Corner Fixed):
             // Width grows by 10px.
             // So dScale = 10 / Width.
             // This matches my formula. 
             // BUT, does the visual edge move 10px? 
             // Visual Edge = Center + 0.5 * Scale * Width.
             // If I am compensating center shift...
             // New Edge = (Center + Shift) + 0.5 * (Scale + dS) * Width.
             
             dS = (dSX + dSY); // Basic combination
             
             // Check polarity match (prevent fighting)
             if (dSX.sign != dSY.sign && dSX != 0 && dSY != 0) {
                 // Dragging perpendicular to diagonal? Ignore?
                 dS = dSX; // Prefer Width
             }
         } else {
             // Side handle (not possible with current UI which only has corners)
             dS = (dSX != 0) ? dSX : dSY;
         }
         
         dSX = dS;
         dSY = dS; 
      }

      double finalSX = initialSX + dSX;
      double finalSY = initialSY + dSY;
      
      // 4. ANCHORING LOGIC (The "Shift")
      // We moved the edge by (dSX * W). 
      // Center must shift by (dSX * W) / 2 in the direction of the handle.
      
      double localShiftX = (finalSX - initialSX) * intrinsicSize.width / 2.0;
      double localShiftY = (finalSY - initialSY) * intrinsicSize.height / 2.0;
      
      // If expanding Right (handleX > 0), Center moves Right (+).
      // If expanding Left (handleX < 0), Center moves Left (-).
      // Logic handles this automatically: dSX contains sign.
      // Wait. dSX = +0.1 (Grow). 
      // If Right Handle: we want Center to move Right (+). shift = +0.05 * W.
      // If Left Handle: we want Center to move Left (-). shift = -0.05 * W.
      // But dSX is +0.1 for BOTH cases if growing.
      // So we must multiply by handle sign.

      if (handleAlignment.x != 0) localShiftX *= handleAlignment.x;
      if (handleAlignment.y != 0) localShiftY *= handleAlignment.y;
      
      if (widget.lockAspect) {
          // If locked, we need to enforce anchor on the stationary corner.
          // Handle TopRight -> Anchor BottomLeft.
          // Shift X moves Right (+). Shift Y moves Up (-).
          // handleX=1, handleY=-1.
          // localShiftX (+) OK. localShiftY (-) OK.
          // It works.
      }
      
      // Rotate Shift into Global Space
      // Shift is vector in object's local unrotated space.
      // GlobalShift = Rotate(Shift, rotation)
      
      // ROTATION CORRECTION:
      double rot = _initialTransform!.rotation * pi / 180.0;
      double globalShiftX = localShiftX * cos(rot) - localShiftY * sin(rot);
      double globalShiftY = localShiftX * sin(rot) + localShiftY * cos(rot);
      
      widget.onUpdate(MediaTransform(
         scaleX: finalSX,
         scaleY: finalSY,
         translateX: _initialTransform!.translateX + globalShiftX,
         translateY: _initialTransform!.translateY + globalShiftY,
         rotation: _initialTransform!.rotation,
         crop: _initialTransform!.crop
      ));
  }

  void _onCropHandleUpdate(DragUpdateDetails details, Alignment handleAlignment) {
      if (_initialTransform == null || _dragStart == null) return;

      Size size = const Size(100, 100);
      if (_contentKey.currentContext != null) {
          final box = _contentKey.currentContext!.findRenderObject() as RenderBox;
          size = box.size;
      }

      Offset globalDelta = details.globalPosition - _dragStart!;
      
      double rotRad = -_initialTransform!.rotation * pi / 180.0;
      double dx_local_px = globalDelta.dx * cos(rotRad) - globalDelta.dy * sin(rotRad);
      double dy_local_px = globalDelta.dx * sin(rotRad) + globalDelta.dy * cos(rotRad);
      
      double sX = _initialTransform!.scaleX;
      double sY = _initialTransform!.scaleY;
      if (sX == 0) sX = 1; 
      if (sY == 0) sY = 1;

      // Normalize by Scale
      double dx_content = dx_local_px / sX;
      double dy_content = dy_local_px / sY;

      double dxPct = (dx_content / size.width) * 100;
      double dyPct = (dy_content / size.height) * 100;
      
      final c = _initialTransform!.crop!;
      double x = c.x;
      double y = c.y;
      double w = c.width;
      double h = c.height;

      // Top Left
      if (handleAlignment == Alignment.topLeft) {
         x += dxPct;
         y += dyPct;
         w -= dxPct;
         h -= dyPct;
      }
      // Top Right
      if (handleAlignment == Alignment.topRight) {
         y += dyPct;
         w += dxPct;
         h -= dyPct;
      }
      // Bottom Left
      if (handleAlignment == Alignment.bottomLeft) {
         x += dxPct;
         w -= dxPct;
         h += dyPct;
      }
      // Bottom Right
      if (handleAlignment == Alignment.bottomRight) {
         w += dxPct;
         h += dyPct;
      }
      
      widget.onUpdate(MediaTransform(
        scaleX: _initialTransform!.scaleX,
        scaleY: _initialTransform!.scaleY,
        translateX: _initialTransform!.translateX,
        translateY: _initialTransform!.translateY,
        rotation: _initialTransform!.rotation,
        crop: CropInfo(x: x, y: y, width: w, height: h),
      ));
  }

  void _onRotateUpdate(DragUpdateDetails details, Size gizmoSize) {
      final RenderBox box = context.findRenderObject() as RenderBox;
      final center = box.localToGlobal(box.size.center(Offset.zero));
      
      final touch = details.globalPosition;
      final angle = atan2(touch.dy - center.dy, touch.dx - center.dx);
      
      // Convert to degrees and apply offset (handle is at -90 deg / top)
      double degrees = (angle * 180 / pi) + 90;
      
      widget.onUpdate(MediaTransform(
        scaleX: widget.transform.scaleX,
        scaleY: widget.transform.scaleY,
        translateX: widget.transform.translateX,
        translateY: widget.transform.translateY,
        rotation: degrees,
        crop: widget.transform.crop,
      ));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isCropMode) {
        // Crop mode logic handled inside layout builder
    }
    
    final t = widget.transform;
    
    // Dynamic Padding
    final double sX = t.scaleX.abs();
    final double sY = t.scaleY.abs();
    
    return LayoutBuilder(
      builder: (context, constraints) {
          double pX = 0;
          double pY = 0;
          
          if (widget.contentSize != null) {
              pX = (constraints.maxWidth - widget.contentSize!.width) / 2;
              pY = (constraints.maxHeight - widget.contentSize!.height) / 2;
              if (pX < 0) pX = 0;
              if (pY < 0) pY = 0;
          }
          final double padX = pX;
          final double padY = pY;
    
          return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // 1. The Content (Child) transformed.
              Transform(
                  transform: Matrix4.identity()
                    ..translate(t.translateX, t.translateY)
                    ..rotateZ(t.rotation * pi / 180)
                    ..scale(t.scaleX, t.scaleY),
                  alignment: Alignment.center,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                         // LAYER 1: Video Content (Background)
                         Padding(
                           padding: EdgeInsets.symmetric(horizontal: padX, vertical: padY),
                           child: KeyedSubtree(
                             key: _contentKey,
                             child: widget.child,
                           ),
                         ),
                         
                         // LAYER 2: Pan Handler (Covers video + padding)
                         // Captures drag events for Pan, blocking video controls if they conflict
                         _buildPanHandler(),
                         
                         // LAYER 3: Crop UI (If active)
                         // Padding applied inside _buildCropUI via Positioned offsets to avoid ParentDataWidget error
                         if(widget.isSelected && widget.showOutline && widget.isCropMode && widget.editMode == EditMode.crop && t.crop != null) 
                            _buildCropUI(t.crop!, t, padX, padY),
  
                         // LAYER 4: Standard UI (Zoom handles)
                         // Positioned with explicit offsets, sits on top
                         if(widget.isSelected && widget.showOutline && widget.editMode == EditMode.zoom)
                            ..._buildStandardUI(t, padX, padY),
                      ],
                    ),
              ),
          ],
        );
      },
    );
  }
  
  // New: Builds the Crop Overlay (Positioned rect based on %)
  Widget _buildCropUI(CropInfo crop, MediaTransform t, double padX, double padY) {      
      return Positioned(
        left: padX,
        top: padY,
        right: padX,
        bottom: padY,
        child: LayoutBuilder(
          builder: (context, constraints) {
            double w = constraints.maxWidth;
            double h = constraints.maxHeight;
            
            double cx = w * (crop.x / 100);
            double cy = h * (crop.y / 100);
            double cw = w * (crop.width / 100);
            double ch = h * (crop.height / 100);

            return Stack(
              children: [
                // Dimmed Overlay - WRAPPED IN IGNORE POINTER
                IgnorePointer(
                  child: Stack(
                    children: [
                       Positioned(top: 0, left: 0, right: 0, height: cy, child: Container(color: Colors.black54)),
                       Positioned(bottom: 0, left: 0, right: 0, height: h - (cy + ch), child: Container(color: Colors.black54)),
                       Positioned(top: cy, bottom: h - (cy + ch), left: 0, width: cx, child: Container(color: Colors.black54)),
                       Positioned(top: cy, bottom: h - (cy + ch), right: 0, width: w - (cx + cw), child: Container(color: Colors.black54)),
                    ],
                  ),
                ),
                
                // Crop Rect Border - Explicit Opaque Hit Test
                Positioned(
                  left: cx, top: cy, width: cw, height: ch,
                  child: GestureDetector(
                    onPanStart: _onPanStart,
                    onPanUpdate: _onTranslateUpdate, 
                    behavior: HitTestBehavior.opaque, // Ensures we catch the drag
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2.0),
                        color: Colors.transparent, 
                      ),
                    ),
                  ),
                ),
                
                // Crop Handles (Corners of Crop Rect)
                // NO OFFSET needed here because we are inside the Padded Stack -> Positioned relative to Video
                _buildAbsoluteHandle(cx, cy, Alignment.topLeft, t.scaleX, t.scaleY),
                _buildAbsoluteHandle(cx + cw, cy, Alignment.topRight, t.scaleX, t.scaleY),
                _buildAbsoluteHandle(cx, cy + ch, Alignment.bottomLeft, t.scaleX, t.scaleY),
                _buildAbsoluteHandle(cx + cw, cy + ch, Alignment.bottomRight, t.scaleX, t.scaleY),
              ],
            );
          },
      ),
      ); 
  }

  Widget _buildPanHandler() {
      return Positioned.fill(
         child: Listener(
           onPointerDown: (_) => debugPrint("Gizmo: POINTER DOWN!"),
           onPointerUp: (_) => debugPrint("Gizmo: POINTER UP!"),
           child: GestureDetector(
             behavior: HitTestBehavior.opaque, // FORCE OPAQUE capture
             onPanStart: (d) { debugPrint("Gizmo: PanStart"); _onPanStart(d); },
             onPanUpdate: _onTranslateUpdate,
             onDoubleTap: widget.onDoubleTap,
             child: Container(color: Colors.transparent),  
           ),
         )
      );
  }
  
  List<Widget> _buildStandardUI(MediaTransform t, double padX, double padY) {
       // Global Scale for constant visual size
       double globalScale = _getGlobalScaleFactor();
       if (globalScale == 0) globalScale = 1.0;

       return [
           // Border (around Video)
           // Needs offset because it's in the Padded Stack
          Positioned(
            left: padX, top: padY, right: padX, bottom: padY,
            child: IgnorePointer(
              child: Container(
                 decoration: BoxDecoration(
                   // Compensation for Non-Uniform Scale
                   border: Border(
                      top: BorderSide(color: Colors.blueAccent, width: (2.0 / globalScale)),
                      bottom: BorderSide(color: Colors.blueAccent, width: (2.0 / globalScale)),
                      left: BorderSide(color: Colors.blueAccent, width: (2.0 / globalScale)),
                      right: BorderSide(color: Colors.blueAccent, width: (2.0 / globalScale)),
                   ),
                 ),
              ),
            ),
          ),
          // Handles
          _buildHandle(Alignment.topLeft, t.scaleX, padX, padY),
          _buildHandle(Alignment.topRight, t.scaleX, padX, padY),
          _buildHandle(Alignment.bottomLeft, t.scaleX, padX, padY),
          _buildHandle(Alignment.bottomRight, t.scaleX, padX, padY),
          
        ];
  }
  
  Widget _buildAbsoluteHandle(double x, double y, Alignment align, double sX, double sY) {
     // CONSTANT VISUAL SIZE HANDLES
     // We want the handle to be 48px visually on Screen.
     // LocalSize = ScreenSize / GlobalScale.
     double globalScale = _getGlobalScaleFactor();
     if (globalScale == 0) globalScale = 1.0;
     
     // UN-SCALE Logic:
     // Visual Size = LogicSize * LocalScale * GlobalScale.
     // We want Visual Size = 48.
     // LogicSize = 48 / (GlobalScale).
     // Note: Handles are OUTSIDE the transform, so we do NOT divide by sX/sY.
     
     double safeSX = sX.abs(); if (safeSX < 0.001) safeSX = 0.001;
     double safeSY = sY.abs(); if (safeSY < 0.001) safeSY = 0.001;
     
     // INCREASED HIT AREA TO 150px (was 96)
     double w = (200.0 / globalScale);
     double h = (200.0 / globalScale);
     
     return Positioned(
       left: x - (w / 2), 
       top: y - (h / 2),
       child: GestureDetector(
         onPanStart: _onPanStart,
         onPanUpdate: (d) => _onScaleUpdate(d, align), 
         behavior: HitTestBehavior.opaque,
         child: Container(
           width: w,
           height: h,
           color: Colors.transparent, // Hit area
           alignment: Alignment.center,
           child: Container(
             width: (32 / globalScale),
             height: (32 / globalScale),
             color: Colors.yellowAccent,
           ),
         ),
       ),
     );
  }
  
  Widget _buildHandle(Alignment align, double scale, double padX, double padY) {
     double globalScale = _getGlobalScaleFactor();
     if (globalScale == 0) globalScale = 1.0;
     
     double safeSX = scale.abs(); if (safeSX < 0.001) safeSX = 0.001;
     double safeSY = widget.transform.scaleY.abs(); if (safeSY < 0.001) safeSY = 0.001;

     // INCREASED HIT AREA TO 150px (Radius 75)
     double radiusX = (100.0 / globalScale);
     double radiusY = (100.0 / globalScale);
     
     return Positioned(
       left: align.x < 0 ? (padX - radiusX) : null, 
       right: align.x > 0 ? (padX - radiusX) : null,
       top: align.y < 0 ? (padY - radiusY) : null,
       bottom: align.y > 0 ? (padY - radiusY) : null,
       child: GestureDetector(
         behavior: HitTestBehavior.opaque,
         onPanStart: _onPanStart,
         onPanUpdate: (d) => _onScaleUpdate(d, align),
         child: Container(
           width: (200.0 / globalScale),
           height: (200.0 / globalScale),
           color: Colors.transparent, // Hit area
           alignment: Alignment.center,
           child: Container(
             width: (32.0 / globalScale),
             height: (32.0 / globalScale),
             color: Colors.blue,
           ),
         ),
       ),
     );
  }
}
