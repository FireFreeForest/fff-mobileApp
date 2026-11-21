import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/date_format_utils.dart';

class AggregateChart extends StatelessWidget {
  const AggregateChart({
    super.key,
    required this.environment,
    required this.fire,
  });

  final Map<String, dynamic>? environment;
  final Map<String, dynamic>? fire;

  @override
  Widget build(BuildContext context) {
    final envPoints = _points(environment);
    final firePoints = _points(fire);
    final empty = envPoints.isEmpty && firePoints.isEmpty;

    if (empty) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'Belum ada data agregat pada rentang ini.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (envPoints.isNotEmpty) ...[
          Text(
            'LINGKUNGAN',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(letterSpacing: 1, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          _SeriesChart(
            points: envPoints,
            valueKeys: const ['temperature', 'humidity', 'soil_moisture'],
            labels: const ['Suhu', 'Udara', 'Tanah'],
            colors: const [
              AppColors.danger,
              AppColors.primary,
              AppColors.success,
            ],
            height: 180,
            normalized: true,
          ),
        ],
        if (firePoints.isNotEmpty) ...[
          Text(
            'API & ASAP',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(letterSpacing: 1, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          _SeriesChart(
            points: firePoints,
            valueKeys: const ['smoke_level', 'flame_level'],
            labels: const ['Asap ADC', 'Api ADC'],
            colors: const [AppColors.primaryDark, AppColors.danger],
            height: 150,
          ),
        ],
      ],
    );
  }

  List<Map<String, dynamic>> _points(Map<String, dynamic>? data) {
    final raw = data?['points'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}

class _SeriesChart extends StatelessWidget {
  const _SeriesChart({
    required this.points,
    required this.valueKeys,
    required this.labels,
    required this.colors,
    required this.height,
    this.normalized = false,
  });

  final List<Map<String, dynamic>> points;
  final List<String> valueKeys;
  final List<String> labels;
  final List<Color> colors;
  final double height;
  final bool normalized;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('Tidak ada data')),
      );
    }

    return Column(
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: 4,
          children: [
            for (var i = 0; i < labels.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors[i],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    labels[i],
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _AggregatePainter(
              points: points,
              valueKeys: valueKeys,
              colors: colors,
              normalized: normalized,
              gridColor: context.appBorder,
            ),
          ),
        ),
        if (points.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _pointTime(points.first),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(fontSize: 9),
                ),
                Text(
                  _pointTime(points.last),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(fontSize: 9),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _pointTime(Map<String, dynamic> point) {
    final raw =
        point['bucket_start']?.toString() ?? point['recorded_at']?.toString();
    final date = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    return date == null ? '' : formatWibTime(date);
  }
}

class _AggregatePainter extends CustomPainter {
  _AggregatePainter({
    required this.points,
    required this.valueKeys,
    required this.colors,
    required this.normalized,
    required this.gridColor,
  });

  final List<Map<String, dynamic>> points;
  final List<String> valueKeys;
  final List<Color> colors;
  final bool normalized;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 8.0;
    const bottom = 8.0;
    const left = 4.0;
    const right = 4.0;
    final width = size.width - left - right;
    final height = size.height - top - bottom;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8;
    for (var i = 0; i <= 4; i++) {
      final y = top + height * i / 4;
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
    }

    for (var series = 0; series < valueKeys.length; series++) {
      final key = valueKeys[series];
      final values = points.map((point) {
        final value = point[key];
        return value is num ? value.toDouble() : null;
      }).toList();

      final valid = values.whereType<double>().toList();
      if (valid.isEmpty) continue;

      final rawMax = normalized
          ? (key == 'temperature'
                ? 60.0
                : key == 'humidity'
                ? 100.0
                : 1023.0)
          : math.max(1023.0, valid.reduce(math.max));

      final offsets = <Offset>[];
      for (var i = 0; i < values.length; i++) {
        final value = values[i];
        if (value == null) continue;
        final x = values.length == 1
            ? left + width / 2
            : left + width * i / (values.length - 1);
        final y = top + height - (value / rawMax).clamp(0.0, 1.0) * height;
        offsets.add(Offset(x, y));
      }
      if (offsets.isEmpty) continue;

      final paint = Paint()
        ..color = colors[series]
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final fillPaint = Paint()..color = colors[series].withValues(alpha: 0.08);
      final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (final offset in offsets.skip(1)) {
        path.lineTo(offset.dx, offset.dy);
      }

      if (offsets.length > 1) {
        final fill = Path()
          ..addPath(path, Offset.zero)
          ..lineTo(offsets.last.dx, top + height)
          ..lineTo(offsets.first.dx, top + height)
          ..close();
        canvas.drawPath(fill, fillPaint);
      }
      canvas.drawPath(path, paint);
      for (final offset in offsets) {
        canvas.drawCircle(offset, 1.8, Paint()..color = colors[series]);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AggregatePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.valueKeys != valueKeys ||
        oldDelegate.normalized != normalized ||
        oldDelegate.gridColor != gridColor;
  }
}
