import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics/analytics.dart';
import '../core/analytics/time_range.dart';
import '../state/app_state.dart';
import 'theme.dart';

String bucketLabel(DateTime d, Bucket b) => switch (b) {
      Bucket.day => AmountFormat.dateShort.format(d),
      Bucket.week => AmountFormat.dateShort.format(d),
      Bucket.month => AmountFormat.monthShort.format(d),
      Bucket.quarter => 'Q${(d.month - 1) ~/ 3 + 1} ${d.year % 100}',
      Bucket.year => '${d.year}',
    };

/// Saldoverlauf: Linie + Fläche, Ziehen zeigt Datum und Saldo.
class BalanceChart extends ConsumerStatefulWidget {
  final List<(DateTime, int)> points;
  final double height;
  const BalanceChart({super.key, required this.points, this.height = 150});

  @override
  ConsumerState<BalanceChart> createState() => _BalanceChartState();
}

class _BalanceChartState extends ConsumerState<BalanceChart> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final discreet = ref.watch(discreetProvider);
    final pts = widget.points;
    if (pts.length < 2) {
      return SizedBox(height: widget.height, child: Center(child: Text('Noch keine Verlaufsdaten', style: theme.textTheme.bodySmall)));
    }
    final values = pts.map((p) => p.$2).toList();
    final minV = values.reduce(math.min), maxV = values.reduce(math.max);
    final up = values.last >= values.first;
    final line = up ? AppColors.pos(context) : AppColors.neg(context);
    final idx = _hover;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      int indexAt(double dx) => ((dx / w) * (pts.length - 1)).round().clamp(0, pts.length - 1);
      void update(Offset p) {
        final i = indexAt(p.dx);
        if (i != _hover) {
          HapticFeedback.selectionClick();
          setState(() => _hover = i);
        }
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 20,
          child: idx == null
              ? Row(children: [
                  Expanded(
                    child: Text('Höchststand ${AmountFormat.compact(maxV, discreet: discreet)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary)),
                  ),
                  Expanded(
                    child: Text('Tiefststand ${AmountFormat.compact(minV, discreet: discreet)}',
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary)),
                  ),
                ])
              : Text(
                  '${AmountFormat.date.format(pts[idx].$1)} · ${AmountFormat.format(pts[idx].$2, discreet: discreet)}',
                  style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => update(d.localPosition),
          onHorizontalDragUpdate: (d) => update(d.localPosition),
          onHorizontalDragEnd: (_) => setState(() => _hover = null),
          onTapDown: (d) => update(d.localPosition),
          onTapUp: (_) => setState(() => _hover = null),
          child: CustomPaint(
            size: Size(w, widget.height),
            painter: _LinePainter(values: values, color: line, grid: theme.colorScheme.outline, hover: idx, zeroLine: minV < 0 && maxV > 0),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Text(AmountFormat.date.format(pts.first.$1), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary)),
          const Spacer(),
          Text(AmountFormat.date.format(pts.last.$1), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary)),
        ]),
      ]);
    });
  }
}

class _LinePainter extends CustomPainter {
  final List<int> values;
  final Color color;
  final Color grid;
  final int? hover;
  final bool zeroLine;

  _LinePainter({required this.values, required this.color, required this.grid, this.hover, this.zeroLine = false});

  @override
  void paint(Canvas canvas, Size size) {
    final minV = values.reduce(math.min).toDouble();
    final maxV = values.reduce(math.max).toDouble();
    final range = (maxV - minV).abs() < 1 ? 1.0 : maxV - minV;
    final lo = minV - range * 0.08, hi = maxV + range * 0.08;
    double x(int i) => size.width * i / (values.length - 1);
    double y(num v) => size.height * (1 - (v - lo) / (hi - lo));

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 0.5;
    for (var i = 1; i <= 3; i++) {
      canvas.drawLine(Offset(0, size.height * i / 4), Offset(size.width, size.height * i / 4), gridPaint);
    }
    if (zeroLine) {
      canvas.drawLine(Offset(0, y(0)), Offset(size.width, y(0)), gridPaint..strokeWidth = 1);
    }

    final path = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(x(i), y(values[i]));
    }
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    if (hover != null) {
      final hx = x(hover!), hy = y(values[hover!]);
      canvas.drawLine(Offset(hx, 0), Offset(hx, size.height), Paint()..color = grid..strokeWidth = 1);
      canvas.drawCircle(Offset(hx, hy), 5, Paint()..color = color);
      canvas.drawCircle(Offset(hx, hy), 2.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.values != values || old.hover != hover || old.color != color;
}

/// Einnahmen (grün) und Ausgaben (rot) je Zeitabschnitt. Antippen zeigt Werte.
class CashflowChart extends ConsumerStatefulWidget {
  final List<CashflowBucket> buckets;
  final Bucket bucket;
  final double height;
  final bool showIncome;
  const CashflowChart({super.key, required this.buckets, required this.bucket, this.height = 140, this.showIncome = true});

  @override
  ConsumerState<CashflowChart> createState() => _CashflowChartState();
}

class _CashflowChartState extends ConsumerState<CashflowChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final discreet = ref.watch(discreetProvider);
    final b = widget.buckets;
    if (b.isEmpty) return SizedBox(height: widget.height);
    final maxV = b.fold<int>(1, (m, x) => math.max(m, math.max(widget.showIncome ? x.incomeCents : 0, x.expenseCents)));
    final inc = AppColors.pos(context), exp = AppColors.neg(context);
    final sel = _selected != null && _selected! < b.length ? b[_selected!] : null;
    final labelEvery = (b.length / 6).ceil().clamp(1, 1000);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 20,
        child: sel == null
            ? Row(children: [
                if (widget.showIncome) ...[_legend(theme, inc, 'Einnahmen'), const SizedBox(width: 12)],
                _legend(theme, exp, 'Ausgaben'),
              ])
            : Text(
                '${bucketLabel(sel.start, widget.bucket)}: '
                '${widget.showIncome ? '+${AmountFormat.format(sel.incomeCents, discreet: discreet, round: true)} / ' : ''}'
                '−${AmountFormat.format(sel.expenseCents, discreet: discreet, round: true)}',
                style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: widget.height,
        child: LayoutBuilder(builder: (context, c) {
          final slot = c.maxWidth / b.length;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => setState(() {
              final i = (d.localPosition.dx / slot).floor().clamp(0, b.length - 1);
              _selected = _selected == i ? null : i;
            }),
            onHorizontalDragUpdate: (d) => setState(() => _selected = (d.localPosition.dx / slot).floor().clamp(0, b.length - 1)),
            child: CustomPaint(
              size: Size(c.maxWidth, widget.height),
              painter: _CashflowPainter(b, maxV, inc, exp, theme.colorScheme.outline, _selected, widget.showIncome),
            ),
          );
        }),
      ),
      const SizedBox(height: 4),
      Row(children: [
        for (var i = 0; i < b.length; i++)
          Expanded(
            child: i % labelEvery == 0
                ? Text(bucketLabel(b[i].start, widget.bucket),
                    maxLines: 1, overflow: TextOverflow.visible, softWrap: false,
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary, fontSize: 10))
                : const SizedBox.shrink(),
          ),
      ]),
    ]);
  }

  Widget _legend(ThemeData theme, Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary)),
      ]);
}

class _CashflowPainter extends CustomPainter {
  final List<CashflowBucket> b;
  final int maxV;
  final Color inc, exp, grid;
  final int? selected;
  final bool showIncome;
  _CashflowPainter(this.b, this.maxV, this.inc, this.exp, this.grid, this.selected, this.showIncome);

  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / b.length;
    final gap = math.max(1.0, slot * 0.18);
    final barW = showIncome ? (slot - gap) / 2 : slot - gap;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), Paint()..color = grid);
    for (var i = 0; i < b.length; i++) {
      final dim = selected != null && selected != i;
      final x0 = i * slot + gap / 2;
      final r = Radius.circular(math.min(4, barW / 2));
      void bar(double x, int v, Color c) {
        final h = (v / maxV) * size.height;
        if (h <= 0) return;
        canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(x, size.height - h, barW, h), topLeft: r, topRight: r),
          Paint()..color = dim ? c.withValues(alpha: 0.3) : c,
        );
      }

      if (showIncome) {
        bar(x0, b[i].incomeCents, inc);
        bar(x0 + barW, b[i].expenseCents, exp);
      } else {
        bar(x0, b[i].expenseCents, exp);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CashflowPainter old) => old.b != b || old.selected != selected || old.inc != inc;
}

/// Donut mit max. 6 Segmenten + „Sonstiges“, Summe in der Mitte.
class DonutChart extends ConsumerWidget {
  final List<(String label, int cents, Color color)> segments;
  final String centerTitle;
  final double size;
  const DonutChart({super.key, required this.segments, this.centerTitle = 'Ausgaben', this.size = 170});

  static List<(String, int, Color)> condense(List<(String, int, Color)> s, {int max = 6}) {
    if (s.length <= max) return s;
    final rest = s.skip(max - 1).fold<int>(0, (a, e) => a + e.$2);
    return [...s.take(max - 1), ('Sonstiges', rest, const Color(0xFF9A9EA5))];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final discreet = ref.watch(discreetProvider);
    final segs = condense(segments);
    final total = segs.fold<int>(0, (a, s) => a + s.$2);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(size: Size.square(size), painter: _DonutPainter(segs, theme.colorScheme.outline)),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(centerTitle, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary)),
          Text(AmountFormat.compact(total, discreet: discreet), style: theme.textTheme.titleMedium),
        ]),
      ]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<(String, int, Color)> segments;
  final Color empty;
  _DonutPainter(this.segments, this.empty);

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<int>(0, (a, s) => a + s.$2.abs());
    final center = size.center(Offset.zero);
    const stroke = 18.0;
    final rect = Rect.fromCircle(center: center, radius: size.width / 2 - stroke / 2);
    if (total == 0) {
      canvas.drawArc(rect, 0, 2 * math.pi, false, Paint()..color = empty..style = PaintingStyle.stroke..strokeWidth = stroke);
      return;
    }
    const gapAngle = 0.035;
    var start = -math.pi / 2;
    for (final s in segments) {
      final sweep = s.$2.abs() / total * 2 * math.pi;
      final drawSweep = segments.length > 1 ? math.max(0.01, sweep - gapAngle) : sweep;
      canvas.drawArc(
        rect,
        start + (segments.length > 1 ? gapAngle / 2 : 0),
        drawSweep,
        false,
        Paint()
          ..color = s.$3
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.segments != segments;
}

/// Einfache Balken mit Beschriftung (z. B. Wochentage); höchster Wert hervorgehoben.
class LabeledBars extends ConsumerWidget {
  final List<(String label, int cents)> bars;
  final double height;
  const LabeledBars({super.key, required this.bars, this.height = 110});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final discreet = ref.watch(discreetProvider);
    if (bars.isEmpty) return const SizedBox.shrink();
    final maxV = bars.map((b) => b.$2).reduce(math.max);
    final maxIdx = bars.indexWhere((b) => b.$2 == maxV);
    return SizedBox(
      height: height + 36,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < bars.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(AmountFormat.compact(bars[i].$2, discreet: discreet),
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(fontSize: 9, color: theme.colorScheme.secondary)),
                const SizedBox(height: 2),
                Container(
                  height: maxV <= 0 ? 2 : math.max(2, bars[i].$2 / maxV * height),
                  decoration: BoxDecoration(
                    color: i == maxIdx ? theme.colorScheme.primary : theme.colorScheme.primary.withValues(alpha: 0.3),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(bars[i].$1, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Kleiner Monatsverlauf (z. B. für einen Händler).
class MiniBars extends StatelessWidget {
  final List<(DateTime, int)> values;
  final double height;
  final Color? color;
  const MiniBars({super.key, required this.values, this.height = 48, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    final maxV = values.fold<int>(1, (m, v) => math.max(m, v.$2));
    return SizedBox(
      height: height + 16,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final v in values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(
                  height: math.max(2, v.$2 / maxV * height),
                  decoration: BoxDecoration(color: v.$2 > 0 ? c : c.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(height: 3),
                Text(AmountFormat.monthShort.format(v.$1).substring(0, 1),
                    style: theme.textTheme.labelSmall?.copyWith(fontSize: 9, color: theme.colorScheme.secondary)),
              ]),
            ),
          ),
      ]),
    );
  }
}
