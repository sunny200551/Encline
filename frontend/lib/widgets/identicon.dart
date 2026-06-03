import 'package:flutter/material.dart';

class IdenticonWidget extends StatelessWidget {
  final String publicKeyHex;
  final double size;

  const IdenticonWidget({
    Key? key,
    required this.publicKeyHex,
    this.size = 40.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (publicKeyHex.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.person, size: size * 0.6, color: Colors.grey),
      );
    }

    // Generate a deterministic base color from the public key hex
    final Color mainColor = _getColorFromHex(publicKeyHex);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            mainColor.withValues(alpha: 0.15),
            mainColor.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(
          color: mainColor.withValues(alpha: 0.3),
          width: 1.0,
        ),
      ),
      child: ClipOval(
        child: CustomPaint(
          size: Size(size, size),
          painter: _IdenticonPainter(publicKeyHex, mainColor),
        ),
      ),
    );
  }

  Color _getColorFromHex(String hex) {
    int sum = 0;
    for (int i = 0; i < hex.length; i++) {
      sum += hex.codeUnitAt(i);
    }
    // Deterministic hue from 0 to 360
    final double hue = (sum * 17) % 360;
    // Vibrancy adjustments (65% saturation, 50% lightness for excellent contrast)
    return HSLColor.fromAHSL(1.0, hue, 0.65, 0.50).toColor();
  }
}

class _IdenticonPainter extends CustomPainter {
  final String hex;
  final Color fillColors;

  _IdenticonPainter(this.hex, this.fillColors);

  @override
  void paint(Canvas canvas, Size size) {
    final double cellSize = size.width / 5;
    final paint = Paint()
      ..color = fillColors
      ..style = PaintingStyle.fill;

    // A 5x5 grid is horizontally symmetrical, so we only need to parse 3 columns:
    // Columns: 0, 1, 2. Columns 3 and 4 mirror 1 and 0.
    // We map 15 cells (5 rows * 3 columns). We parse 15 hex characters starting from index 2.
    final int startOffset = hex.length > 17 ? 2 : 0;

    for (int r = 0; r < 5; r++) {
      for (int c = 0; c < 3; c++) {
        final charIndex = startOffset + (r * 3 + c);
        if (charIndex >= hex.length) continue;
        
        final char = hex[charIndex];
        final val = int.tryParse(char, radix: 16) ?? 0;
        
        // Filled if the hex value is even
        final isFilled = val % 2 == 0;

        if (isFilled) {
          final rectL = Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize);
          final rectR = Rect.fromLTWH((4 - c) * cellSize, r * cellSize, cellSize, cellSize);
          
          final rrectL = RRect.fromRectAndRadius(rectL, Radius.circular(cellSize * 0.3));
          final rrectR = RRect.fromRectAndRadius(rectR, Radius.circular(cellSize * 0.3));
          
          canvas.drawRRect(rrectL, paint);
          if (c < 2) {
            canvas.drawRRect(rrectR, paint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IdenticonPainter oldDelegate) {
    return oldDelegate.hex != hex || oldDelegate.fillColors != fillColors;
  }
}
