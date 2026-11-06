import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/nav.dart';
import '../bank/sync_ui.dart';
import '../charts.dart';
import '../screens/accounts_screen.dart';
import '../screens/merchant_detail.dart';
import '../screens/settings_screen.dart';
import '../screens/transaction_detail.dart';
import '../theme.dart';
import '../widgets.dart';

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final store = ref.read(storeProvider);
    final engine = ref.read(engineProvider);
    final p = ref.watch(currentPeriodProvider);
    final theme = Theme.of(context);

    final visible = store.accounts.where((a) => a.includeInTotal && !a.hidden).toList();
    final total = visible.fold<int>(0, (a, acc) => a + acc.balanceCents);
    final startBalance = p.balance.isNotEmpty ? p.balance.first.$2 : total;
    final balanceChange = total - startBalance;

    final now = DateTime.now();
    final upcoming = store.contracts
        .where((c) => c.status == ContractStatus.aktiv && c.nextDue != null && c.nextDue!.difference(now).inDays <= 30)
        .toList()
      ..sort((a, b) => a.nextDue!.compareTo(b.nextDue!));
    final upcomingSum = upcoming.fold<int>(0, (a, c) => a + c.expectedCents);

    final open = store.insights.where((i) => !i.dismissed).toList()
      ..sort((a, b) => (b.potentialCentsPerYear ?? 0).compareTo(a.potentialCentsPerYear ?? 0));
    final potential = open.fold<int>(0, (a, i) => a + (i.potentialCentsPerYear ?? 0));
    final errors = store.connections.where((c) => c.lastError != null).toList();

    final recent = [...store.transactions]..sort((a, b) => b.bookingDate.compareTo(a.bookingDate));

    void openSpending(SpendingView v) {
      ref.read(spendingViewProvider.notifier).set(v);
      ref.read(tabProvider.notifier).go(AppTab.spending);
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => refreshAll(context, ref),
        child: CustomScrollView(slivers: [
          SliverAppBar(
            title: const Text('Klarblick'),
            floating: true,
            actions: [
              if (app.syncing || app.analyzing)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (store.connections.isNotEmpty && bankingSupported)
                IconButton(icon: const Icon(Icons.sync), tooltip: 'Konten aktualisieren', onPressed: () => refreshAll(context, ref)),
              IconButton(
                icon: Icon(ref.watch(discreetProvider) ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                tooltip: 'Beträge verbergen',
                onPressed: () => store.updateSettings({'discreetMode': !(store.settings['discreetMode'] == true)}),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Einstellungen',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList.list(children: [
              if (store.loadError != null) ...[
                InfoBanner(text: store.loadError!, color: AppColors.warn(context), icon: Icons.warning_amber_outlined),
                const SizedBox(height: 8),
              ],
              for (final c in errors) ...[
                InfoBanner(
                  text: '${c.bankName}: ${c.lastError}',
                  color: AppColors.neg(context),
                  icon: Icons.error_outline,
                  actionLabel: bankingSupported ? 'Erneut' : null,
                  onAction: () => syncConnectionInteractive(context, ref, c),
                ),
                const SizedBox(height: 8),
              ],
              Text('Gesamtsaldo', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AmountText(total, style: theme.textTheme.displayLarge),
              ),
              Row(children: [
                AmountText(balanceChange, signed: true, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(p.range.label.toLowerCase(),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary), overflow: TextOverflow.ellipsis),
                ),
              ]),
              const SizedBox(height: 12),
              const RangeSelector(),
              const SizedBox(height: 12),
              AppCard(
                child: BalanceChart(points: p.balance),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: StatTile(
                    label: 'Einnahmen',
                    cents: p.summary.incomeCents,
                    delta: p.incomeChangePct,
                    goodWhenUp: true,
                    color: AppColors.pos(context),
                    onTap: () {
                      ref.read(txFilterProvider.notifier).set(const TxFilter(kind: TxKind.income, onlyRange: true));
                      ref.read(tabProvider.notifier).go(AppTab.transactions);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    label: 'Ausgaben',
                    cents: p.summary.expenseCents,
                    delta: p.expenseChangePct,
                    color: AppColors.neg(context),
                    onTap: () => openSpending(SpendingView.categories),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    label: 'Übrig',
                    caption: p.summary.savingsRate != null ? 'Quote ${AmountFormat.percent(p.summary.savingsRate!)}' : null,
                    cents: p.summary.netCents,
                    color: p.summary.netCents >= 0 ? AppColors.pos(context) : AppColors.neg(context),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              AppCard(
                title: 'Einnahmen & Ausgaben',
                subtitle: '${p.range.label} · Ø ${AmountFormat.format(p.summary.avgPerMonthCents, discreet: ref.watch(discreetProvider), round: true)} Ausgaben/Monat',
                child: CashflowChart(buckets: p.cashflow, bucket: p.bucket),
              ),
              const SizedBox(height: 12),
              if (p.categories.isNotEmpty)
                AppCard(
                  title: 'Wofür',
                  subtitle: 'Größte Ausgabenbereiche',
                  onSeeAll: () => openSpending(SpendingView.categories),
                  child: Column(children: [
                    for (final c in p.categories.take(4))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          Avatar(icon: categoryIcon(engine.categoryById(c.categoryId)?.icon), color: parseHexColor(c.color), size: 34),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(c.name, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
                                AmountText(c.cents, style: theme.textTheme.bodyMedium, round: true),
                              ]),
                              const SizedBox(height: 4),
                              ShareBar(share: c.share, color: parseHexColor(c.color)),
                            ]),
                          ),
                        ]),
                      ),
                  ]),
                ),
              const SizedBox(height: 12),
              if (p.merchants.isNotEmpty)
                AppCard(
                  title: 'Wo',
                  subtitle: 'Firmen, bei denen am meisten Geld bleibt',
                  onSeeAll: () => openSpending(SpendingView.merchants),
                  child: Column(children: [
                    for (final m in p.merchants.take(5))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Avatar(label: m.name, color: parseHexColor(engine.categoryById(m.categoryId)?.color), size: 34),
                        title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${m.count}× · ${m.recurring ? 'regelmäßig' : 'Ø ${AmountFormat.format(m.avgCents, discreet: ref.watch(discreetProvider))}'}'),
                        trailing: AmountText(m.cents, style: theme.textTheme.bodyMedium, round: true),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MerchantDetailScreen(stat: m))),
                      ),
                  ]),
                ),
              const SizedBox(height: 12),
              AppCard(
                title: 'Sparpotenzial',
                onSeeAll: () => ref.read(tabProvider.notifier).go(AppTab.savings),
                seeAllLabel: 'Ansehen',
                child: open.isEmpty
                    ? Text('Aktuell keine Spar-Hinweise. Gut gemacht!', style: theme.textTheme.bodySmall)
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          AmountText(potential, style: theme.textTheme.titleLarge?.copyWith(color: AppColors.pos(context)), round: true),
                          const SizedBox(width: 6),
                          Text('pro Jahr möglich', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
                        ]),
                        const SizedBox(height: 8),
                        for (final i in open.take(3))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              Icon(Icons.lightbulb_outline, size: 16, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(child: Text(i.title, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ]),
                          ),
                      ]),
              ),
              const SizedBox(height: 12),
              AppCard(
                title: 'Demnächst fällig',
                subtitle: upcoming.isEmpty ? null : 'In 30 Tagen: ${AmountFormat.format(upcomingSum, discreet: ref.watch(discreetProvider))}',
                onSeeAll: () => ref.read(tabProvider.notifier).go(AppTab.contracts),
                child: upcoming.isEmpty
                    ? Text('Keine anstehenden Abbuchungen erkannt.', style: theme.textTheme.bodySmall)
                    : Column(children: [
                        for (final c in upcoming.take(5))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Avatar(label: c.name, color: parseHexColor(engine.categoryById(c.categoryId)?.color), size: 34),
                            title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(_dueLabel(c.nextDue!, now)),
                            trailing: AmountText(-c.expectedCents, style: theme.textTheme.bodyMedium),
                          ),
                      ]),
              ),
              const SizedBox(height: 12),
              AppCard(
                title: 'Konten',
                onSeeAll: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountsScreen())),
                seeAllLabel: 'Verwalten',
                child: Column(children: [
                  for (final a in store.accounts.where((a) => !a.hidden))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Avatar(icon: _accountIcon(a.type), color: parseHexColor(a.color), size: 34),
                      title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          if (a.iban.length > 8) '•••• ${a.iban.substring(a.iban.length - 4)}',
                          if (a.lastSync != null) 'aktualisiert ${AmountFormat.dateShort.format(a.lastSync!)}',
                          if (!a.includeInTotal) 'nicht im Gesamtsaldo',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: AmountText(a.balanceCents, style: theme.textTheme.bodyMedium),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              AppCard(
                title: 'Letzte Umsätze',
                onSeeAll: () {
                  ref.read(txFilterProvider.notifier).reset();
                  ref.read(tabProvider.notifier).go(AppTab.transactions);
                },
                child: recent.isEmpty
                    ? Text('Noch keine Umsätze.', style: theme.textTheme.bodySmall)
                    : Column(children: [
                        for (final t in recent.take(5))
                          TransactionRow(
                            t: t,
                            title: ref.read(analyticsProvider).merchantDisplay(t),
                            category: engine.categoryById(t.categoryId),
                            showDate: true,
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TransactionDetailScreen(transactionId: t.id))),
                          ),
                      ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  static String _dueLabel(DateTime due, DateTime now) {
    final days = DateTime(due.year, due.month, due.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days <= 0) return 'heute';
    if (days == 1) return 'morgen';
    return 'in $days Tagen · ${AmountFormat.dateShort.format(due)}';
  }

  static IconData _accountIcon(AccountType t) => switch (t) {
        AccountType.kreditkarte => Icons.credit_card,
        AccountType.tagesgeld => Icons.savings_outlined,
        AccountType.depot => Icons.show_chart,
        AccountType.bargeld => Icons.payments_outlined,
        _ => Icons.account_balance_outlined,
      };
}
