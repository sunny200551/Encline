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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Use a very light shadow in light mode so it doesn't bleed through the glass filter
    final shadowColor = isDark 
        ? Colors.black.withOpacity(0.25) 
        : Colors.black.withOpacity(0.02);

    final shadowBlur = isDark ? 24.0 : 16.0;
    final shadowSpread = isDark ? -4.0 : -4.0;

    // Soft gray border in light mode instead of a invisible white border
    final borderColor = isDark 
        ? Colors.white.withOpacity(borderOpacity) 
        : Colors.black.withOpacity(0.06);

    // Increase opacity in light mode to block shadow bleeding and maintain crisp white glass surface
    final gradientColors = isDark 
        ? [
            Colors.white.withOpacity(backgroundOpacity + 0.05),
            Colors.white.withOpacity(backgroundOpacity),
          ]
        : [
            Colors.white.withOpacity(0.85),
            Colors.white.withOpacity(0.70),
          ];

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: shadowBlur,
            spreadRadius: shadowSpread,
            offset: isDark ? const Offset(0, 0) : const Offset(0, 4),
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
                color: borderColor,
                width: isDark ? 1.5 : 1.0,
              ),
              gradient: LinearGradient(
                colors: gradientColors,
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
