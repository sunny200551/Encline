import 'dart:ui';
import 'package:flutter/material.dart';

class GlassmorphicContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blur;
  final double borderOpacity;
  final double backgroundOpacity;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  const GlassmorphicContainer({
    Key? key,
    required this.child,
    this.borderRadius = 16,
    this.blur = 12,
    this.borderOpacity = 0.1,
    this.backgroundOpacity = 0.05,
    this.padding,
    this.margin,
    this.width,
    this.height,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 24,
            spreadRadius: -4,
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: Colors.white.withOpacity(borderOpacity),
                width: 1.5,
              ),
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(backgroundOpacity + 0.05),
                  Colors.white.withOpacity(backgroundOpacity),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
