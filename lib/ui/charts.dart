import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// Kontostand-Linie: 2 pt Accent, Fläche 12 % → 0 %, drei Hairlines,
/// Scrub zeigt Datum + Saldo, Prognose gestrichelt.
class LineChart extends StatefulWidget {
  final List<(DateTime date, int cents)> points;
  final int? forecastCents;
  final DateTime? forecastDate;
  final Color? lineColor;

  const LineChart({super.key, required this.points, this.forecastCents, this.forecastDate, this.lineColor});

  @override
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart> {
  int? hoverIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = widget.lineColor ?? theme.colorScheme.primary;
    if (widget.points.length < 2) {
      return SizedBox(height: 120, child: Center(child: Text('Noch keine Verlaufsdaten', style: theme.textTheme.bodySmall)));
    }
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = 120.0;
      final all = [...widget.points];
      if (widget.forecastCents != null && widget.forecastDate != null) {
        all.add((widget.forecastDate!, widget.forecastCents!));
      }
      final minV = all.map((p) => p.$2).reduce(math.min).toDouble();
      final maxV = all.map((p) => p.$2).reduce(math.max).toDouble();
      final range = (maxV - minV).abs() < 1 ? 1.0 : (maxV - minV);
      final pad = range * 0.08;
      final lo = minV - pad, hi = maxV + pad;

      double x(int i) => 8 + (w - 16) * (all.length == 1 ? 0.5 : i / (all.length - 1));
      double y(int v) => 8 + (h - 16) * (1 - (v - lo) / (hi - lo));

      return GestureDetector(
        onHorizontalDragUpdate: (d) {
          final i = ((d.localPosition.dx - 8) / (w - 16) * (all.length - 1)).round().clamp(0, all.length - 1);
          if (i != hoverIndex) setState(() => hoverIndex = i);
        },
        onHorizontalDragEnd: (_) => setState(() => hoverIndex = null),
        onTapUp: (_) => setState(() => hoverIndex = null),
        child: SizedBox(
          height: h + 20,
          child: Stack(children: [
            CustomPaint(
              size: Size(w, h),
              painter: _LinePainter(
                points: all,
                x: x,
                y: y,
                lineColor: line,
                forecastIndex: widget.forecastCents != null ? widget.points.length : null,
                separatorColor: theme.colorScheme.outline,
              ),
            ),
            if (hoverIndex != null && hoverIndex! < all.length)
              Positioned(
                left: x(hoverIndex!).clamp(0, w - 90),
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outline),
                  ),
                  child: Text(
                    '${AmountFormat.dateShort.format(all[hoverIndex!].$1)} ${AmountFormat.format(all[hoverIndex!].$2)}',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
          ]),
        ),
      );
    });
  }
}

class _LinePainter extends CustomPainter {
  final List<(DateTime, int)> points;
  final double Function(int) x;
  final double Function(int) y;
  final Color lineColor;
  final int? forecastIndex;
  final Color separatorColor;

  _LinePainter({required this.points, required this.x, required this.y, required this.lineColor, this.forecastIndex, required this.separatorColor});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final px = x(i), py = y(points[i].$2);
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    for (var i = 1; i <= 3; i++) {
      final hy = size.height * i / 4;
      final paint = Paint()
        ..color = separatorColor.withValues(alpha: 0.6)
        ..strokeWidth = 0.5;
      canvas.drawLine(Offset(0, hy), Offset(size.width, hy), paint);
    }
    final area = Path.from(path)
      ..lineTo(x(points.length - 1), size.height)
      ..lineTo(x(0), size.height)
      ..close();
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [lineColor.withValues(alpha: 0.12), lineColor.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(area, fill);

    final solid = Path();
    final split = forecastIndex ?? points.length;
    for (var i = 0; i < points.length; i++) {
      final px = x(i), py = y(points[i].$2);
      if (i < split) {
        if (i == 0) {
          solid.moveTo(px, py);
        } else {
          solid.lineTo(px, py);
        }
      }
    }
    canvas.drawPath(
      solid,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    if (forecastIndex != null && points.length >= 2) {
      final dashed = Path();
      dashed.moveTo(x(split - 1), y(points[split - 1].$2));
      for (var i = split; i < points.length; i++) {
        dashed.lineTo(x(i), y(points[i].$2));
      }
      final dashPaint = Paint()
        ..color = lineColor.withValues(alpha: 0.6)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      _drawDashedPath(canvas, dashed, dashPaint, 5, 4);
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint, double dash, double gap) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final len = math.min(dash, metric.length - distance);
        canvas.drawPath(metric.extractPath(distance, distance + len), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Donut: Ring 14 pt, 2° Lücke, max. 6 Segmente + „Sonstiges“, Summe in der Mitte.
class DonutChart extends StatelessWidget {
  final List<(String label, int cents, Color color)> segments;
  final String centerLabel;

  const DonutChart({super.key, required this.segments, required this.centerLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 180,
      child: Row(children: [
        SizedBox(
          width: 180,
          height: 180,
          child: CustomPaint(painter: _DonutPainter(segments)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(centerLabel, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final s in segments.take(6))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: s.$3, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s.$1, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    AmountText(s.$2, style: theme.textTheme.bodySmall),
                  ]),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<(String, int, Color)> segments;
  _DonutPainter(this.segments);

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<int>(0, (a, s) => a + s.$2.abs());
    if (total == 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 7;
    var start = -math.pi / 2;
    for (final s in segments) {
      final sweep = (s.$2.abs() / total) * 2 * math.pi - (2 * math.pi / 360) * 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep.clamp(0.01, 2 * math.pi),
        false,
        Paint()
          ..color = s.$3
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round,
      );
      start += sweep + (2 * math.pi / 360) * 2;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Balken (Monatsvergleich): oben gerundet, aktueller Monat accent.
class BarChart extends StatelessWidget {
  final List<(String label, int cents)> bars;
  final bool positive;

  const BarChart({super.key, required this.bars, this.positive = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (bars.isEmpty) return const SizedBox.shrink();
    final maxV = bars.map((b) => b.$2.abs()).reduce(math.max).toDouble().clamp(1, double.infinity);
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < bars.length; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: FractionallySizedBox(
                      heightFactor: (bars[i].$2.abs() / maxV).clamp(0.02, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: i == bars.length - 1 ? theme.colorScheme.primary : theme.colorScheme.secondary.withValues(alpha: 0.4),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(bars[i].$1, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
