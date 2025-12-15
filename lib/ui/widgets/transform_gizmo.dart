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
  final Widget child;

  const TransformGizmo({
    super.key,
    required this.transform,
    required this.onUpdate,
    required this.child,
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

  void _onTranslateUpdate(DragUpdateDetails details) {
     if (_initialTransform == null) return;
     
     // CROP MODE: Pan moves the CROP RECT
     if (widget.isCropMode && widget.editMode == EditMode.crop && widget.transform.crop != null) {
       // We need context size to convert pixels to %
       final RenderBox box = context.findRenderObject() as RenderBox;
       final size = box.size;
       
       double dxPct = (details.globalPosition.dx - _dragStart!.dx) / size.width * 100;
       double dyPct = (details.globalPosition.dy - _dragStart!.dy) / size.height * 100;
       
       // Update Crop X/Y
       final initialCrop = _initialTransform!.crop!;
       
       // Clamp to 0-100 logic? Maybe later.
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
      
      // Calculate Global Delta to avoid Local-Coordinate confusion inside Transform
      // However, details.delta is local.
      // To get stable interaction, let's look at the widget's render box size.
      
      final RenderBox box = context.findRenderObject() as RenderBox;
      final size = box.size; // This is the visual size of the gizmo (transformed)
      
      // Prevent division by zero
      if (size.width < 1 || size.height < 1) return;

      // Mouse delta in local coordinates (which is skewed by transform scale)
      // Actually, if we use the fraction of the box, we can be agnostic to coordinate space?
      // box.globalToLocal(details.globalPosition) - box.globalToLocal(lastPos) ??
      // Let's use details.delta assuming simpler relationship for now, 
      // but normalize by the current visual size.
      // If I drag 10% of the box width, I want the box to grow by 10%?
      // Yes. dS = (delta / dimension) * S.
      
      if (_initialTransform == null || _dragStart == null) return;

      // GLOBAL DELTA STRATEGY
      // This bypasses all local scaling / coordinate confusion.
      Offset globalDelta = details.globalPosition - _dragStart!;
      
      // We must un-rotate this delta to align with the object's local X/Y axes.
      // If rotation is 0, global X = local X.
      // If rotation is 90, global X = local -Y?
      double rotRad = -_initialTransform!.rotation * pi / 180.0; // Negative to un-rotate
      double dx_local = globalDelta.dx * cos(rotRad) - globalDelta.dy * sin(rotRad);
      double dy_local = globalDelta.dx * sin(rotRad) + globalDelta.dy * cos(rotRad);

      // 1. Get Intrinsic Size
      Size intrinsicSize = const Size(100, 100); 
      if (_contentKey.currentContext != null) {
          final box = _contentKey.currentContext!.findRenderObject() as RenderBox;
          intrinsicSize = box.size;
      }
      
      // 2. Calculate Scaled Change relative to Intrinsic Size
      // dScale = LocalPixels / IntrinsicPixels
      double dScaleX = dx_local / intrinsicSize.width;
      double dScaleY = dy_local / intrinsicSize.height;
      
      // 3. Apply to INITIAL scale (not current) to avoid drift
      double newScaleX = _initialTransform!.scaleX;
      double newScaleY = _initialTransform!.scaleY;

      if (widget.lockAspect) {
        // Use average relative change or dominant axis?
        // Dragging corner: use distance? 
        // Simple: Avg of X/Y contribution.
        
        // Adjust polarity based on handle
        double contribution = 0;
        if (handleAlignment == Alignment.topRight) contribution = dScaleX - dScaleY;
        if (handleAlignment == Alignment.topLeft) contribution = -dScaleX - dScaleY;
        if (handleAlignment == Alignment.bottomRight) contribution = dScaleX + dScaleY;
        if (handleAlignment == Alignment.bottomLeft) contribution = -dScaleX + dScaleY;
        
        // Improve feel: average the normalized changes?
        // Or just use the max?
        // Let's assume uniform box -> intrinsic W approx H. 
        // Just Use contribution directly.
        
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

      // GLOBAL DELTA STRATEGY (Same as Scale)
      Offset globalDelta = details.globalPosition - _dragStart!;
      
      // Un-rotate
      double rotRad = -_initialTransform!.rotation * pi / 180.0;
      double dx_local = globalDelta.dx * cos(rotRad) - globalDelta.dy * sin(rotRad);
      double dy_local = globalDelta.dx * sin(rotRad) + globalDelta.dy * cos(rotRad);

      // Get Intrinsic Size
      Size intrinsicSize = const Size(100, 100);
      if (_contentKey.currentContext != null) {
          final box = _contentKey.currentContext!.findRenderObject() as RenderBox;
          intrinsicSize = box.size;
      }
      
      // Calculate Percentage Change
      // 100% = Full Width
      // dx_pct = (dx_pixels / intrinsic_pixels) * 100
      double dxPct = (dx_local / intrinsicSize.width) * 100;
      double dyPct = (dy_local / intrinsicSize.height) * 100;
      
      final c = _initialTransform!.crop!; // USE INITIAL CROP
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
                child: IntrinsicWidth(
                  child: IntrinsicHeight(
                    child: Stack(
                      key: _contentKey,
                      clipBehavior: Clip.none,
                      children: [
                         // Main content
                         widget.child,

                         // PAN HANDLER (Always active for moving the video)
                         // Placed here so it sits on top of child but below specific handles
                         _buildPanHandler(),

                         // CROP MODE UI (Only if in Crop sub-mode)
                         if(widget.isCropMode && widget.editMode == EditMode.crop && t.crop != null) 
                            _buildCropUI(t.crop!),

                         // STANDARD MODE UI (Only if in Zoom sub-mode)
                         if(widget.isCropMode && widget.editMode == EditMode.zoom)
                            ..._buildStandardUI(t),
                      ],
                    ),
                  ),
                )
            ),
          ],
        );
      },
    );
  }
  
  // New: Builds the Crop Overlay (Positioned rect based on %)
  Widget _buildCropUI(CropInfo crop) {      
      return Positioned.fill(
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
                // Dimmed Overlay
                // Top
                Positioned(top: 0, left: 0, right: 0, height: cy, child: Container(color: Colors.black54)),
                // Bottom
                Positioned(bottom: 0, left: 0, right: 0, height: h - (cy + ch), child: Container(color: Colors.black54)),
                // Left (middle)
                Positioned(top: cy, bottom: h - (cy + ch), left: 0, width: cx, child: Container(color: Colors.black54)),
                // Right (middle)
                Positioned(top: cy, bottom: h - (cy + ch), right: 0, width: w - (cx + cw), child: Container(color: Colors.black54)),
                
                // The Crop Rect Border
                Positioned(
                  left: cx, top: cy, width: cw, height: ch,
                  child: GestureDetector(
                    onPanStart: _onPanStart,
                    onPanUpdate: _onTranslateUpdate, // Moves crop rect
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2.0),
                        color: Colors.transparent, // Hit test?
                      ),
                    ),
                  ),
                ),
                
                // Crop Handles (Corners of Crop Rect)
                _buildAbsoluteHandle(cx, cy, Alignment.topLeft),
                _buildAbsoluteHandle(cx + cw, cy, Alignment.topRight),
                _buildAbsoluteHandle(cx, cy + ch, Alignment.bottomLeft),
                _buildAbsoluteHandle(cx + cw, cy + ch, Alignment.bottomRight),
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
           child: Container(color: Colors.transparent), 
         )
      );
  }
  
  List<Widget> _buildStandardUI(MediaTransform t) {
      return [

          // Border
         Positioned.fill(
           child: IgnorePointer(
             child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blueAccent, width: (2.0 / t.scaleX).abs()),
                ),
             ),
           ),
         ),
         // Handles
         _buildHandle(Alignment.topLeft, t.scaleX),
         _buildHandle(Alignment.topRight, t.scaleX),
         _buildHandle(Alignment.bottomLeft, t.scaleX),
         _buildHandle(Alignment.bottomRight, t.scaleX),
         
         // Rotate
         Positioned(
           top: -30 / t.scaleY.abs(),
           left: 0,
           right: 0,
           child: Center(
             child: GestureDetector(
               onPanStart: (d) => _onPanStart(d),
               onPanUpdate: (d) => _onRotateUpdate(d, Size.zero),
               child: Container(
                 width: (20 / t.scaleX).abs(),
                 height: (20 / t.scaleY).abs(),
                 decoration: const BoxDecoration(
                   color: Colors.green,
                   shape: BoxShape.circle,
                 ),
               ),
             ),
           ),
         )
      ];
  }
  
  Widget _buildAbsoluteHandle(double x, double y, Alignment align) {
     return Positioned(
       left: x - 10,
       top: y - 10,
       child: GestureDetector(
         onPanStart: _onPanStart,
         onPanUpdate: (d) => _onScaleUpdate(d, align), // reuse scale logic which calls crop update
         child: Container(
           width: 20,
           height: 20,
           color: Colors.yellowAccent,
         ),
       ),
     );
  }
  
  Widget _buildHandle(Alignment align, double scale) {
     final s = scale.abs();
     return Positioned(
       left: align.x < 0 ? -10.0 / s : null, // Offset to center on corner
       right: align.x > 0 ? -10.0 / s : null,
       top: align.y < 0 ? -10.0 / s : null,
       bottom: align.y > 0 ? -10.0 / s : null,
       child: GestureDetector(
         behavior: HitTestBehavior.translucent,
         onPanStart: _onPanStart,
         onPanUpdate: (d) => _onScaleUpdate(d, align),
         child: Container(
           width: 20.0 / s,
           height: 20.0 / s,
           color: Colors.blue,
         ),
       ),
     );
  }
}
