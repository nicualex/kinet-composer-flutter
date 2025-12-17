import 'dart:ui';
import 'package:flutter/material.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final Color tint;
  final Border? border;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 15.0,
    this.opacity = 0.1,
    this.padding = const EdgeInsets.all(20.0),
    this.borderRadius,
    this.tint = Colors.white,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: opacity),
            borderRadius: borderRadius ?? BorderRadius.circular(16),
            border: border ?? Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: child,
        ),
      ),
    );
  }
}
