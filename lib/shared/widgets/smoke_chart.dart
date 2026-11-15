import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/telemetry.dart';

class SmokeChart extends StatelessWidget {
  const SmokeChart({
    super.key,
    required this.readings,
    required this.threshold,
  });

  final List<TelemetryFire> readings;
  final int threshold;

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) {
      return SizedBox(
        height: 132,
        child: Center(
          child: Text(
            'Belum ada riwayat asap.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.textMuted),
          ),
        ),
      );
    }

    return SizedBox(
      height: 132,
      width: double.infinity,
      child: CustomPaint(
        painter: _SmokeChartPainter(
          readings: readings,
          threshold: threshold,
          lineColor: AppColors.primary,
          fillColor: AppColors.primary.withValues(alpha: 0.18),
          gridColor: AppColors.border,
          thresholdColor: AppColors.danger,
        ),
      ),
    );
  }
}

class _SmokeChartPainter extends CustomPainter {
  const _SmokeChartPainter({
    required this.readings,
    required this.threshold,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.thresholdColor,
  });

  final List<TelemetryFire> readings;
  final int threshold;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  final Color thresholdColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 0.0;
    const right = 0.0;
    const top = 8.0;
    const bottom = 8.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    final values = readings.map((reading) => reading.smokeLevel).toList();
    final rawMax = values.fold<int>(0, math.max);
    final maxValue = math.max(600, math.max(threshold, rawMax)).toDouble();
    final maxY = maxValue * 1.15;

    double yFor(num value) {
      final normalized = (value / maxY).clamp(0.0, 1.0).toDouble();
      return top + chartHeight - (normalized * chartHeight);
    }

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.7;
    for (var i = 0; i <= 2; i++) {
      final y = top + (chartHeight / 2) * i;
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
    }

    final thresholdPaint = Paint()
      ..color = thresholdColor
      ..strokeWidth = 1;
    final thresholdY = yFor(threshold);
    final dashWidth = 5.0;
    final dashSpace = 4.0;
    var x = left;
    while (x < size.width - right) {
      canvas.drawLine(
        Offset(x, thresholdY),
        Offset(math.min(x + dashWidth, size.width - right), thresholdY),
        thresholdPaint,
      );
      x += dashWidth + dashSpace;
    }

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? left + chartWidth / 2
          : left + (chartWidth / (values.length - 1)) * i;
      points.add(Offset(x, yFor(values[i])));
    }

    if (points.length == 1) {
      final point = points.first;
      canvas.drawCircle(point, 3.5, Paint()..color = lineColor);
      return;
    }

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }

    final fillPath = Path()
      ..addPath(linePath, Offset.zero)
      ..lineTo(points.last.dx, top + chartHeight)
      ..lineTo(points.first.dx, top + chartHeight)
      ..close();

    canvas.drawPath(fillPath, Paint()..color = fillColor);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final dotPaint = Paint()..color = lineColor;
    for (final point in points) {
      canvas.drawCircle(point, 2.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SmokeChartPainter oldDelegate) {
    return oldDelegate.readings != readings ||
        oldDelegate.threshold != threshold ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.thresholdColor != thresholdColor;
  }
}
