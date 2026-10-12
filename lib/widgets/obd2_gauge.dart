import 'dart:math' as math;
import 'package:flutter/material.dart';

class Obd2RadialGauge extends StatelessWidget {
  final double value;
  final double minValue;
  final double maxValue;
  final double redlineValue;
  final String title;
  final String unit;
  final Color accentColor;
  final double size;

  const Obd2RadialGauge({
    super.key,
    required this.value,
    this.minValue = 0.0,
    this.maxValue = 8000.0,
    this.redlineValue = 6500.0,
    required this.title,
    required this.unit,
    required this.accentColor,
    this.size = 220.0,
  });

  @override
  Widget build(BuildContext context) {
    final clampedVal = value.clamp(minValue, maxValue);
    final isRedlining = clampedVal >= redlineValue;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RadialGaugePainter(
              value: clampedVal,
              minValue: minValue,
              maxValue: maxValue,
              redlineValue: redlineValue,
              accentColor: accentColor,
              isRedlining: isRedlining,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 100),
                style: TextStyle(
                  fontSize: size * 0.18,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  color: isRedlining ? const Color(0xFFFF3366) : Colors.white,
                  shadows: [
                    Shadow(
                      color: isRedlining
                          ? const Color(0xFFFF3366).withValues(alpha: 0.8)
                          : accentColor.withValues(alpha: 0.5),
                      blurRadius: isRedlining ? 16 : 8,
                    ),
                  ],
                ),
                child: Text(
                  value >= 1000
                      ? (value / 1000).toStringAsFixed(1)
                      : value.toStringAsFixed(0),
                ),
              ),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: isRedlining
                      ? const Color(0xFFFF3366)
                      : accentColor,
                ),
              ),
            ],
          ),
          if (isRedlining)
            Positioned(
              top: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3366),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF3366).withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Text(
                  'SHIFT',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RadialGaugePainter extends CustomPainter {
  final double value;
  final double minValue;
  final double maxValue;
  final double redlineValue;
  final Color accentColor;
  final bool isRedlining;

  _RadialGaugePainter({
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.redlineValue,
    required this.accentColor,
    required this.isRedlining,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 16;
    const startAngle = 135.0 * (math.pi / 180.0);
    const sweepAngle = 270.0 * (math.pi / 180.0);

    // 1. Background Arc Track
    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // 2. Redline Zone Background Arc
    final redlineFraction =
        (redlineValue - minValue) / (maxValue - minValue);
    final redlineStartAngle = startAngle + (sweepAngle * redlineFraction);
    final redlineSweep = sweepAngle * (1.0 - redlineFraction);

    final redlineZonePaint = Paint()
      ..color = const Color(0xFFFF3366).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      redlineStartAngle,
      redlineSweep,
      false,
      redlineZonePaint,
    );

    // 3. Active Value Sweep Arc
    final valueFraction = ((value - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);
    final activeSweep = sweepAngle * valueFraction;

    if (activeSweep > 0.001) {
      final activePaint = Paint()
        ..shader = SweepGradient(
          startAngle: startAngle,
          endAngle: startAngle + sweepAngle,
          colors: [
            accentColor,
            accentColor,
            const Color(0xFFFFB300),
            const Color(0xFFFF3366),
          ],
          stops: const [0.0, 0.65, 0.85, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        activeSweep,
        false,
        activePaint,
      );
    }

    // 4. Tick Marks
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1.5;

    final majorTickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 2.5;

    final totalTicks = 32;
    for (int i = 0; i <= totalTicks; i++) {
      final tickAngle = startAngle + (sweepAngle * (i / totalTicks));
      final isMajor = i % 4 == 0;
      final tickLength = isMajor ? 8.0 : 4.0;
      final outerR = radius - 12;
      final innerR = outerR - tickLength;

      final p1 = Offset(
        center.dx + outerR * math.cos(tickAngle),
        center.dy + outerR * math.sin(tickAngle),
      );
      final p2 = Offset(
        center.dx + innerR * math.cos(tickAngle),
        center.dy + innerR * math.sin(tickAngle),
      );

      final isPastRedline =
          (minValue + ((maxValue - minValue) * (i / totalTicks))) >= redlineValue;

      if (isPastRedline) {
        majorTickPaint.color = const Color(0xFFFF3366);
      } else {
        majorTickPaint.color = Colors.white.withValues(alpha: 0.7);
      }

      canvas.drawLine(p1, p2, isMajor ? majorTickPaint : tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadialGaugePainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.isRedlining != isRedlining;
  }
}

class Obd2SensorCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final double ratio; // 0.0 to 1.0
  final Color? barColor;
  final String? subtitle;

  const Obd2SensorCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    this.ratio = 0.0,
    this.barColor,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeBarColor = barColor ?? theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: activeBarColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: activeBarColor,
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
          ],
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(activeBarColor),
            ),
          ),
        ],
      ),
    );
  }
}

class Obd2TelemetryGraph extends StatelessWidget {
  final List<double> values;
  final String label;
  final Color color;
  final double minVal;
  final double maxVal;

  const Obd2TelemetryGraph({
    super.key,
    required this.values,
    required this.label,
    required this.color,
    required this.minVal,
    required this.maxVal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF14171F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                values.isNotEmpty
                    ? '${values.last.toStringAsFixed(0)} curr'
                    : '--',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _TelemetryLinePainter(
                values: values,
                color: color,
                minVal: minVal,
                maxVal: maxVal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TelemetryLinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double minVal;
  final double maxVal;

  _TelemetryLinePainter({
    required this.values,
    required this.color,
    required this.minVal,
    required this.maxVal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final range = (maxVal - minVal) > 0 ? (maxVal - minVal) : 1.0;
    final path = Path();
    final fillPath = Path();

    final stepX = size.width / (values.length - 1);

    for (int i = 0; i < values.length; i++) {
      final normalizedY =
          1.0 - ((values[i] - minVal) / range).clamp(0.0, 1.0);
      final x = i * stepX;
      final y = normalizedY * size.height;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // Fill Gradient
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.25),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    // Line Stroke
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _TelemetryLinePainter oldDelegate) => true;
}
