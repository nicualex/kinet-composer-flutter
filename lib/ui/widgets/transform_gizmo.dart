import 'dart:math';

import 'package:flutter/material.dart';
import '../../models/show_manifest.dart';

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

  const TransformGizmo({
    super.key,
    required this.transform,
    required this.onUpdate,
    required this.child,
    this.onDoubleTap,
    this.isCropMode = false,
    this.lockAspect = true,
    this.editMode = EditMode.zoom, // Default
  });

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
     // This is simple translation in Global Space. 
     // We simply add global delta to global translate?
     // Yes, translateX/Y are translations applied in parent space (usually).
     // Wait, is translate applied *before* rotate/scale or after?
     // Matrix: Translate -> Rotate -> Scale? Or Scale -> Rotate -> Translate?
     // Gizmo build: 
     // ..translate(t.translateX, t.translateY)
     // ..rotateZ...
     // ..scale...
     // This means Translate is applied LAST (closest to root), in Global Frame (if parent is unrotated).
     // PROBABLY correct to just add global delta.
     
     widget.onUpdate(MediaTransform(
       scaleX: _initialTransform!.scaleX,
       scaleY: _initialTransform!.scaleY,
       translateX: _initialTransform!.translateX + (details.globalPosition.dx - _dragStart!.dx),
       translateY: _initialTransform!.translateY + (details.globalPosition.dy - _dragStart!.dy),
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

      // Use Content Size for reference to ensure 1:1 feel
      Size intrinsicSize = const Size(100, 100); 
      if (_contentKey.currentContext != null) {
          final box = _contentKey.currentContext!.findRenderObject() as RenderBox;
          intrinsicSize = box.size;
      }

      Offset globalDelta = details.globalPosition - _dragStart!;
      
      // Un-rotate
      double rotRad = -_initialTransform!.rotation * pi / 180.0; // Negative to un-rotate
      double dx_local = globalDelta.dx * cos(rotRad) - globalDelta.dy * sin(rotRad);
      double dy_local = globalDelta.dx * sin(rotRad) + globalDelta.dy * cos(rotRad);

      // PROPORTIONALITY FIX (VERSION 3 - ROBUST GLOBAL SCALE):
      // 1. Get Global Scale Factor (Screen Pixels per Logic Pixel)
      double globalScale = _getGlobalScaleFactor();
      if (globalScale == 0) globalScale = 1.0;
      
      // 2. Convert Screen Delta -> Logic Delta
      // ScreenDelta / GlobalScale = LogicDelta
      double dx_logic = dx_local / globalScale;
      double dy_logic = dy_local / globalScale;
      
      // 3. Convert Logic Delta -> Scale Delta
      // LogicDelta / IntrinsicSize = ScaleDelta
      // (Since IntrinsicSize is the "100%" basis for scale)

      double currentSX = _initialTransform!.scaleX;
      double currentSY = _initialTransform!.scaleY;
      if (currentSX == 0) currentSX = 1;
      if (currentSY == 0) currentSY = 1;
      
      Size visualSize = intrinsicSize;

      double dScaleX = (dx_logic * currentSX.abs()) / visualSize.width; // Logic vs Logic
      double dScaleY = (dy_logic * currentSY.abs()) / visualSize.height;
      
      // Wait, if visualSize.width is ALREADY scaled by scaleX in logic space?
      // No, visualSize comes from RenderBox.size.
      // If we are observing RenderBox of Child inside Transform...
      // RenderBox sizes are generally unscaled by the Transform above them?
      // Yes. So visualSize.width IS intrinsicSize.width (1920).
      
      // So dScaleX = dx_logic / visualSize.width.
      // Wait, if I drag 100 logic pixels on a 1000px wide object, I want 10% change.
      // So dScaleX = 0.1.
      // So dScaleX = dx_logic / visualSize.width.
      // Is that correct?
      // Original Scale = 1.0. New Scale = 1.1.
      // Visual Width goes 1000 -> 1100. Diff = 100. Correct.
      
      // What if Scale is 2.0?
      // Visual Width is 2000.
      // I drag 100 logic pixels.
      // I expect visual width to go 2000 -> 2100.
      // That is a 5% increase relative to 2000.
      // But scale goes 2.0 -> 2.1?
      // 2.1 * 1000 = 2100.
      // So dScale IS always dx_logic / intrinsicWidth.
      
      dScaleX = dx_logic / visualSize.width;
      dScaleY = dy_logic / visualSize.height;
      
      double newScaleX = _initialTransform!.scaleX;
      double newScaleY = _initialTransform!.scaleY;

      if (widget.lockAspect) {
        // Uniform scaling
        double contribution = 0;
        if (handleAlignment == Alignment.topRight) contribution = dScaleX - dScaleY;
        if (handleAlignment == Alignment.topLeft) contribution = -dScaleX - dScaleY;
        if (handleAlignment == Alignment.bottomRight) contribution = dScaleX + dScaleY;
        if (handleAlignment == Alignment.bottomLeft) contribution = -dScaleX + dScaleY;
        
        newScaleX += contribution;
        newScaleY += contribution; 
      } else {
        // Non-Uniform
        if (handleAlignment == Alignment.topRight) {
             newScaleX += dScaleX;
             newScaleY -= dScaleY;
        } else if (handleAlignment == Alignment.topLeft) {
             newScaleX -= dScaleX;
             newScaleY -= dScaleY;
        } else if (handleAlignment == Alignment.bottomRight) {
             newScaleX += dScaleX;
             newScaleY += dScaleY;
        } else if (handleAlignment == Alignment.bottomLeft) {

             newScaleX -= dScaleX;
             newScaleY += dScaleY;
        }
      }
      
      // MINIMUM SCALE CLAMP (Prevent vanishing)
      if (newScaleX.abs() < 0.3) newScaleX = 0.3 * (newScaleX < 0 ? -1 : 1);
      if (newScaleY.abs() < 0.3) newScaleY = 0.3 * (newScaleY < 0 ? -1 : 1);

      widget.onUpdate(MediaTransform(
        scaleX: newScaleX,
        scaleY: newScaleY,
        translateX: widget.transform.translateX,
        translateY: widget.transform.translateY,
        rotation: widget.transform.rotation,
        crop: widget.transform.crop,
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
    // FORCE NO PADDING TO PREVENT VIDEO SHRINKING
    final double padX = 0; 
    final double padY = 0;
    
    return LayoutBuilder(
      builder: (context, constraints) {
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
                       if(widget.isCropMode && widget.editMode == EditMode.crop && t.crop != null) 
                          _buildCropUI(t.crop!, t, padX, padY),

                       // LAYER 4: Standard UI (Zoom handles)
                       // Positioned with explicit offsets, sits on top
                       if(widget.isCropMode && widget.editMode == EditMode.zoom)
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
         child: GestureDetector(
           behavior: HitTestBehavior.translucent, // Catches taps on empty space
           onPanStart: _onPanStart,
           onPanUpdate: _onTranslateUpdate,
           onDoubleTap: widget.onDoubleTap,
           child: Container(color: Colors.transparent), 
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
                      top: BorderSide(color: Colors.blueAccent, width: (2.0 / globalScale) / t.scaleY.abs()),
                      bottom: BorderSide(color: Colors.blueAccent, width: (2.0 / globalScale) / t.scaleY.abs()),
                      left: BorderSide(color: Colors.blueAccent, width: (2.0 / globalScale) / t.scaleX.abs()),
                      right: BorderSide(color: Colors.blueAccent, width: (2.0 / globalScale) / t.scaleX.abs()),
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
          
           // Rotate
           Positioned(
             top: padY - (40 / globalScale) / t.scaleY.abs(), 
             left: 0,
             right: 0,
             child: Center(
               child: GestureDetector(
                 onPanStart: (d) => _onPanStart(d),
                 onPanUpdate: (d) => _onRotateUpdate(d, Size.zero),
                 behavior: HitTestBehavior.opaque,
                 child: Container(
                   width: (48 / globalScale) / t.scaleX.abs(), 
                   height: (48 / globalScale) / t.scaleY.abs(),
                   color: Colors.transparent, // Hit area
                   alignment: Alignment.center,
                   child: Container(
                     width: (20 / globalScale) / t.scaleX.abs(), 
                     height: (20 / globalScale) / t.scaleY.abs(),
                     decoration: const BoxDecoration(
                       color: Colors.green,
                       shape: BoxShape.circle,
                     ),
                   ),
                 ),
               ),
             ),
           )
        ];
  }
  
  Widget _buildAbsoluteHandle(double x, double y, Alignment align, double sX, double sY) {
     // CONSTANT VISUAL SIZE HANDLES
     // We want the handle to be 48px visually on Screen.
     // LocalSize = ScreenSize / GlobalScale.
     double globalScale = _getGlobalScaleFactor();
     if (globalScale == 0) globalScale = 1.0;
     
     // Note: We also divide by ScaleX/Y because the handle is inside the Scaled Transform?
     // NO. The Handles are OUTSIDE the Transform in the Stack! 
     // Wait, let's check build method.
     // Stack children:
     // 1. Transform(child: Content) 
     // 2. PanHandler
     // 3. Crop UI
     // 4. Standard UI (Handles) -> _buildStandardUI
     
     // The Stack is NOT Scaled. Only the Content is Scaled.
     // So standard handles are in "Logic Space" (1920x1080).
     // They are NOT affected by t.scaleX.
     // BUT we previously divided by sX? "width: 48 / sX".
     // Why? Because we wanted them to stay small relative to the growing object?
     // No, if the object grows, and we want constant handle size, we shouldn't divide.
     
     // Wait, if I scale the object up 2x, the handles are overlay widgets on top.
     // If the Stack size grows... No, the Stack size is determined by `IntrinsicWidth(Stack(Child))`.
     // If `Child` (Video) is 1920x1080, Stack is 1920x1080. 
     // Scale is applied to the Child Transform ONLY?
     // Let's check `_buildStandardUI` call site.
     // It is inside the `Stack`, sibling to `Transform`.
     // So it is in "Logic Space" (1920x1080).
     // "FittedBox" scales this entire Stack down to fit Screen (1000px).
     
     // So, GlobalScale tells us 1 Logic Px = X Screen Px.
     // We want Handle = 48 Screen Px.
     // HandleLogicSize = 48 / GlobalScale.
     
     // UN-SCALE Logic:
     // Visual Size = LogicSize * LocalScale * GlobalScale.
     // We want Visual Size = 48.
     // LogicSize = 48 / (LocalScale * GlobalScale).
     
     double safeSX = sX.abs(); if (safeSX < 0.001) safeSX = 0.001;
     double safeSY = sY.abs(); if (safeSY < 0.001) safeSY = 0.001;
     
     double w = (48.0 / globalScale) / safeSX;
     double h = (48.0 / globalScale) / safeSY;
     
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
             width: (20 / globalScale) / safeSX,
             height: (20 / globalScale) / safeSY,
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
     // Note: _buildHandle assumes Uniform scale for positioning in legacy code, 
     // but here 'scale' input implies uniform? 
     // Wait, _buildStandardUI passes 't.scaleX' to all.
     // If Scale is Non-Uniform, this is wrong.
     // If Unlocked... user can distort.
     // We should fix _buildHandle to take sX and sY.
     // But that requires changing call sites.
     
     // TEMPORARY FIX: Assume uniform unscaling for handles is "okay enough" 
     // OR (Better): Read ScaleY from widget.transform since this is method on State.
     
     double safeSY = widget.transform.scaleY.abs(); if (safeSY < 0.001) safeSY = 0.001;

     double radiusX = (24.0 / globalScale) / safeSX;
     double radiusY = (24.0 / globalScale) / safeSY;
     
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
           width: (48.0 / globalScale) / safeSX,
           height: (48.0 / globalScale) / safeSY,
           color: Colors.transparent, // Hit area
           alignment: Alignment.center,
           child: Container(
             width: (20.0 / globalScale) / safeSX,
             height: (20.0 / globalScale) / safeSY,
             color: Colors.blue,
           ),
         ),
       ),
     );
  }
}
