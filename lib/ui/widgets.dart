import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics/time_range.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// Betrag mit tabellarischen Ziffern, echtem Minus und Diskret-Modus.
class AmountText extends ConsumerWidget {
  final int cents;
  final TextStyle? style;
  final bool signed;
  final bool colorize;
  final bool round;

  const AmountText(this.cents, {super.key, this.style, this.signed = false, this.colorize = true, this.round = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discreet = ref.watch(discreetProvider);
    final text = signed ? AmountFormat.signed(cents, discreet: discreet) : AmountFormat.format(cents, discreet: discreet, round: round);
    final color = signed && colorize && cents > 0 && !discreet ? AppColors.pos(context) : null;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
      style: (style ?? DefaultTextStyle.of(context).style).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color ?? style?.color,
      ),
    );
  }
}

/// Zeitraum-Auswahl 1W · 1M · 3M · 6M · YTD · 1J · 5J · Max – gilt app-weit.
/// Gleichmäßig verteilte Leiste: alle Zeiträume sind ohne Scrollen sichtbar.
class RangeSelector extends ConsumerWidget {
  const RangeSelector({super.key, this.ranges = TimeRange.values});
  final List<TimeRange> ranges;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(rangeProvider);
    final theme = Theme.of(context);
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(children: [
        for (final r in ranges)
          Expanded(
            child: Semantics(
              button: true,
              selected: r == selected,
              label: r.label,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(rangeProvider.notifier).set(r);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: r == selected ? theme.colorScheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      r.short,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: r == selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Karte: Surface, Radius 20, Padding 16, optionaler Titel mit Aktion.
class AppCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final VoidCallback? onSeeAll;
  final String seeAllLabel;
  final Widget child;
  final EdgeInsets padding;
  final Widget? trailing;

  const AppCard({
    super.key,
    this.title,
    this.subtitle,
    this.onSeeAll,
    this.seeAllLabel = 'Alle',
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title!, style: theme.textTheme.headlineMedium),
                      if (subtitle != null)
                        Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
                    ]),
                  ),
                  ?trailing,
                  if (onSeeAll != null)
                    TextButton(
                      onPressed: onSeeAll,
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: Text(seeAllLabel),
                    ),
                ]),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

/// Breiter Haupt-Button (volle Breite des Elternelements).
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  const PrimaryButton({super.key, required this.label, this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: icon == null
            ? FilledButton(onPressed: onPressed, child: Text(label))
            : FilledButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label)),
      );
}

class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  const SecondaryButton({super.key, required this.label, this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: icon == null
            ? FilledButton.tonal(onPressed: onPressed, child: Text(label))
            : FilledButton.tonalIcon(onPressed: onPressed, icon: Icon(icon), label: Text(label)),
      );
}

/// Hinweis-Banner (TAN fällig, Abruf fehlgeschlagen, …).
class InfoBanner extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  const InfoBanner({super.key, required this.text, required this.color, this.icon = Icons.info_outline, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!, style: TextStyle(color: color))),
      ]),
    );
  }
}

/// Leerer Zustand: Icon, ein Satz, optional ein Button.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? buttonLabel;
  final VoidCallback? onButton;

  const EmptyState({super.key, required this.icon, required this.text, this.buttonLabel, this.onButton});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: theme.colorScheme.secondary),
          const SizedBox(height: 12),
          Text(text, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
          if (buttonLabel != null) ...[
            const SizedBox(height: 16),
            PrimaryButton(label: buttonLabel!, onPressed: onButton),
          ],
        ]),
      ),
    );
  }
}

/// Veränderung ggü. Vorperiode. [goodWhenUp]: bei Einnahmen ist „mehr“ gut, bei Ausgaben schlecht.
class DeltaChip extends StatelessWidget {
  final double? pct;
  final bool goodWhenUp;
  final String suffix;
  const DeltaChip(this.pct, {super.key, this.goodWhenUp = false, this.suffix = ''});

  @override
  Widget build(BuildContext context) {
    final p = pct;
    if (p == null || p.isNaN || p.isInfinite) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final neutral = p.abs() < 0.02;
    final good = goodWhenUp ? p > 0 : p < 0;
    final color = neutral ? theme.colorScheme.secondary : (good ? AppColors.pos(context) : AppColors.neg(context));
    final icon = neutral ? Icons.trending_flat : (p > 0 ? Icons.trending_up : Icons.trending_down);
    // Ein einzelner Text (statt Row) – passt sich jeder Breite an, ohne Flex-Fehler.
    return Text.rich(
      TextSpan(children: [
        WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(icon, size: 14, color: color)),
        TextSpan(text: ' ${AmountFormat.percent(p, signed: true)}$suffix'),
      ]),
      style: theme.textTheme.labelSmall?.copyWith(color: color),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Kennzahl-Kachel: Label, Betrag, Veränderung.
class StatTile extends StatelessWidget {
  final String label;
  final int cents;
  final double? delta;
  final bool goodWhenUp;
  final Color? color;
  final IconData? icon;
  final VoidCallback? onTap;

  /// Zusatzzeile, wenn kein Vergleichswert angezeigt wird (z. B. Sparquote).
  final String? caption;

  const StatTile({
    super.key,
    required this.label,
    required this.cents,
    this.delta,
    this.goodWhenUp = false,
    this.color,
    this.icon,
    this.onTap,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 16, color: color ?? theme.colorScheme.secondary), const SizedBox(width: 6)],
              Expanded(
                child: Text(label,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AmountText(cents, style: theme.textTheme.titleMedium?.copyWith(color: color), round: true),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 16,
              child: caption != null
                  ? Text(caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.secondary))
                  : DeltaChip(delta, goodWhenUp: goodWhenUp),
            ),
          ]),
        ),
      ),
    );
  }
}

String initialsOf(String name) {
  final letters = name.replaceAll(RegExp(r'[^A-Za-z0-9ÄÖÜäöüß ]'), ' ').trim();
  if (letters.isEmpty) return '?';
  final parts = letters.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
  return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
}

/// Rundes Symbol für Händler/Kategorie.
class Avatar extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final Color color;
  final double size;

  const Avatar({super.key, this.label, this.icon, required this.color, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(size * 0.3)),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, color: color, size: size * 0.5)
          : Text(initialsOf(label ?? '?'), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: size * 0.36)),
    );
  }
}

/// Anteilsbalken.
class ShareBar extends StatelessWidget {
  final double share;
  final Color color;
  final double height;
  const ShareBar({super.key, required this.share, required this.color, this.height = 6});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          value: share.clamp(0.0, 1.0),
          minHeight: height,
          backgroundColor: color.withValues(alpha: 0.12),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      );
}

/// Zeile eines Umsatzes: Avatar, Händler + Kategorie · Konto, Betrag.
class TransactionRow extends StatelessWidget {
  final Transaction t;
  final Category? category;
  final String title;
  final String accountName;
  final VoidCallback? onTap;
  final bool showDate;

  const TransactionRow({
    super.key,
    required this.t,
    required this.title,
    this.category,
    this.accountName = '',
    this.onTap,
    this.showDate = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catColor = parseHexColor(category?.color);
    final parts = <String>[
      if (showDate) AmountFormat.dateShort.format(t.bookingDate),
      category?.name ?? 'Unkategorisiert',
      if (accountName.isNotEmpty) accountName,
      if (t.pending) 'vorgemerkt',
      if (t.isTransfer) 'Umbuchung',
      if (t.excluded) 'ausgeschlossen',
    ];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(children: [
          Avatar(icon: category != null ? categoryIcon(category!.icon) : null, label: title, color: catColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: theme.textTheme.headlineMedium?.copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(parts.join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 8),
          AmountText(
            t.amountCents,
            signed: true,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: 15,
              color: t.excluded || t.isTransfer ? theme.colorScheme.secondary : null,
            ),
          ),
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
          ?trailing,
        ]),
      );
}

/// Kopieren in die Zwischenablage mit Haptik und Hinweis.
void copyToClipboard(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  HapticFeedback.selectionClick();
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kopiert')));
}

void showSnack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
