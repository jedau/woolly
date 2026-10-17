import 'package:flutter/material.dart';

import 'theme.dart';

/// The Pair mark: two amber tusks, no tile. Paths match brand/logo-options.html.
class PairMark extends StatelessWidget {
  const PairMark({super.key, this.height = 28});

  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(height * 64 / 48, height),
      painter: const _PairPainter(),
    );
  }
}

class WoollyBrand extends StatelessWidget {
  const WoollyBrand({super.key, this.markHeight = 28});

  final double markHeight;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        PairMark(height: markHeight),
        const SizedBox(width: 10),
        Transform.translate(
          offset: const Offset(0, 4),
          child: const Text(
            'WOOLLY',
            textHeightBehavior: TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 1.1, height: 1),
          ),
        ),
      ],
    );
  }
}

class _PairPainter extends CustomPainter {
  const _PairPainter();

  static final Path _left = Path()
    ..moveTo(42, 52)
    ..cubicTo(46, 36, 42, 22, 22, 12)
    ..cubicTo(30, 22, 30, 38, 26, 52)
    ..close();

  static final Path _right = Path()
    ..moveTo(54, 52)
    ..cubicTo(50, 36, 54, 22, 74, 12)
    ..cubicTo(66, 22, 66, 38, 70, 52)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 64;
    final sy = size.height / 48;
    canvas.translate(-16 * sx, -8 * sy);
    canvas.scale(sx, sy);
    final paint = Paint()..color = amber;
    canvas.drawPath(_left, paint);
    canvas.drawPath(_right, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
