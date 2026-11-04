import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import 'theme.dart';

/// AmountText: tabellarische Ziffern, echtes Minus, optional Diskret-Modus.
class AmountText extends StatelessWidget {
  final int cents;
  final TextStyle? style;
  final bool signed;
  final bool discreet;

  const AmountText(this.cents, {super.key, this.style, this.signed = false, this.discreet = false});

  @override
  Widget build(BuildContext context) {
    final text = signed ? AmountFormat.signed(cents, discreet: discreet) : AmountFormat.format(cents, discreet: discreet);
    final color = cents > 0 && signed ? AppColors.positive : null;
    return Text(
      text,
      style: (style ?? DefaultTextStyle.of(context).style).copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            color: color ?? (style?.color),
          ),
    );
  }
}

/// TransactionRow: 64 pt hoch, Avatar 40, Name + Kategorie·Konto, Betrag rechts.
class TransactionRow extends StatelessWidget {
  final Transaction t;
  final Category? category;
  final String accountName;
  final bool discreet;
  final VoidCallback? onTap;

  const TransactionRow({super.key, required this.t, this.category, this.accountName = '', this.discreet = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catColor = category != null ? parseHexColor(category!.color) : AppColors.textTertiaryLight;
    final merchantName = t.counterpartyName.isEmpty ? 'Unbekannt' : t.counterpartyName;
    final monogram = merchantName.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '');
    final initials = monogram.isEmpty
        ? '?'
        : monogram.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).map((p) => p[0]).take(2).join().toUpperCase();
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 64,
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: catColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(initials, style: theme.textTheme.headlineMedium?.copyWith(color: catColor, fontSize: 15))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
               crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text(merchantName, style: theme.textTheme.headlineMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                 Text(
                  '${category?.name ?? 'Unkategoriesiert'} · ${accountName${t.pending ? ' · vorgemerkt' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary),
                  maxLines: 1,
                 overflow: TextOverflow.ellipsis,
                ),
             ],
            ),
            AmountText(t.amountCents, signed: true, discreet: discreet, style: theme.textTheme.headlineMedium),
             ],
            ],
      ),
    );
  }
}

/// Card-Komponente: Surface, Radius 20, Padding 16, optionaler Titel mit „Alle“.
class AppCard extends StatelessWidget {
  final String? title;
  final VoidCallback? onSeeAll;
  final Widget child;
  final EdgeInsets padding;

  const AppCard({super.key, this.title, this.onSeeAll, required this.child, this.padding = const EdgeInsets.all(16)});

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
              Row(children: [
                Text(title!, style: theme.textTheme.headlineMedium),
                const Spacer(),
                if (onSeeAll != null)
                  TextButton(onPressed: onSeeAll, child: const Text('Alle')),
               ],
              ]),
            if (title != null) const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const PrimaryButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) => FilledButton(onPressed: onPressed, child: Text(label));
}

class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const SecondaryButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) => FilledButton.tonal(onPressed: onPressed, child: Text(label));
}

/// Banner für Systemzustände (TAN fällig, Abruf fehlgeschlagen).
class Banner extends StatelessWidget {
  final String text;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  const Banner({super.key, required this.text, required this.color, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(Icons.info_outline, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!, style: TextStyle(color: color))),
      ]),
    );
  }
}

/// EmptyState: feines Icon, ein Satz, ein Button.
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
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: theme.colorScheme.secondary),
          const SizedBox(height: 12),
          Text(text, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
          if (buttonLabel != null) ...[
            const SizedBox(height: 16),
            PrimaryButton(label: buttonLabel!, onPressed: onButton),
          ],
        ]),
      ),
    );
  }
}

/// Kopieren in die Zwischenablage mit Haptik.
void copyToClipboard(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  HapticFeedback.selectionClick();
}
