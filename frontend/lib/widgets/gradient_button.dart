import 'package:flutter/material.dart';
import '../core/constants.dart';

class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Gradient gradient;
  final List<BoxShadow>? glow;
  final IconData? icon;
  final bool isLoading;

  const GradientButton({
    Key? key,
    required this.text,
    required this.onPressed,
    this.gradient = AppColors.primaryGradient,
    this.glow,
    this.icon,
    this.isLoading = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: glow ?? AppGlow.primaryGlow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isLoading ? null : onPressed,
            splashColor: Colors.white.withOpacity(0.15),
            highlightColor: Colors.white.withOpacity(0.05),
            child: Ink(
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Container(
                constraints: const BoxConstraints(minHeight: 50),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
