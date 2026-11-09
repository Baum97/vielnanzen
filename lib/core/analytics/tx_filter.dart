import '../../data/models.dart';

/// Art des Umsatzes im Filter.
enum TxKind { all, expenses, income }

/// Filter der Umsatzliste (auch von anderen Tabs aus gesetzt).
///
/// Die Ebenen bauen aufeinander auf: **Art** (Einnahmen/Ausgaben) → **Kategorie** (Ober- und
/// Unterkategorie) → **Firma**. Konto und Zeitraum sind davon unabhängig.
class TxFilter {
  const TxFilter({
    this.query = '',
    this.kind = TxKind.all,
    this.categoryId,
    this.accountId,
    this.merchantKey,
    this.merchantName,
    this.onlyRange = false,
  });

  final String query;
  final TxKind kind;

  /// Gewählte Kategorie – Oberkategorie oder Unterkategorie ('' = unkategorisiert).
  final String? categoryId;
  final String? accountId;
  final String? merchantKey;
  final String? merchantName;
  final bool onlyRange;

  bool get isEmpty => query.isEmpty && kind == TxKind.all && categoryId == null && accountId == null && merchantKey == null && !onlyRange;

  /// Nur die Auswahl aus Chips (ohne Suchtext).
  bool get hasChipSelection => kind != TxKind.all || categoryId != null || accountId != null || merchantKey != null || onlyRange;

  static const _keep = Object();

  TxFilter copyWith({
    String? query,
    TxKind? kind,
    Object? categoryId = _keep,
    Object? accountId = _keep,
    Object? merchantKey = _keep,
    Object? merchantName = _keep,
    bool? onlyRange,
  }) =>
      TxFilter(
        query: query ?? this.query,
        kind: kind ?? this.kind,
        categoryId: identical(categoryId, _keep) ? this.categoryId : categoryId as String?,
        accountId: identical(accountId, _keep) ? this.accountId : accountId as String?,
        merchantKey: identical(merchantKey, _keep) ? this.merchantKey : merchantKey as String?,
        merchantName: identical(merchantName, _keep) ? this.merchantName : merchantName as String?,
        onlyRange: onlyRange ?? this.onlyRange,
      );

  @override
  bool operator ==(Object other) =>
      other is TxFilter &&
      other.query == query &&
      other.kind == kind &&
      other.categoryId == categoryId &&
      other.accountId == accountId &&
      other.merchantKey == merchantKey &&
      other.onlyRange == onlyRange;

  @override
  int get hashCode => Object.hash(query, kind, categoryId, accountId, merchantKey, onlyRange);
}

/// Die Dimensionen der Filterleiste.
enum FilterDim { kind, category, account, merchant, range }

/// Ein Chip der Filterleiste.
class FilterChipSpec {
  const FilterChipSpec({required this.dim, required this.id, required this.label, this.selected = false, this.count = 0});

  final FilterDim dim;

  /// Art: 'expenses'/'income'; Kategorie: Kategorie-ID; Konto: Konto-ID; Firma: Firmenschlüssel; Zeitraum: 'range'.
  final String id;
  final String label;
  final bool selected;

  /// Anzahl der Umsätze, die dieser Chip (zusätzlich zu den übrigen Filtern) enthält.
  final int count;
}

/// Inhalt der Filterleiste: Gewähltes steht vorn, danach die noch sinnvollen Optionen.
class FilterBar {
  const FilterBar({required this.selected, required this.options});
  final List<FilterChipSpec> selected;
  final List<FilterChipSpec> options;
}

/// Alles, was die Filterlogik von außen braucht.
class TxFilterContext {
  const TxFilterContext({
    required this.categoryOf,
    required this.merchantKey,
    required this.merchantName,
    required this.accountName,
    required this.accountCount,
    required this.rangeFrom,
    required this.rangeLabel,
    required this.searchText,
  });

  final Category? Function(String? id) categoryOf;
  final String Function(Transaction t) merchantKey;
  final String Function(Transaction t) merchantName;
  final String Function(String accountId) accountName;
  final int accountCount;

  /// Beginn des gewählten Zeitraums (für den Chip „nur dieser Zeitraum“).
  final DateTime rangeFrom;
  final String rangeLabel;

  /// Kleingeschriebener Suchtext eines Umsatzes (Firma, Zweck, Notiz, Kategorie, Betrag …).
  final String Function(Transaction t) searchText;
}

/// Wie viele Kategorien höchstens direkt als Chips erscheinen, statt nach Oberkategorien zu gruppieren.
const _flatLimit = 8;
const _merchantLimit = 8;

class _Cats {
  _Cats(this.ctx);
  final TxFilterContext ctx;
  final _cache = <String, List<String>>{};

  /// Pfad von der Oberkategorie bis zur Kategorie, z. B. ['einkommen', 'gehalt'].
  List<String> path(String id) => _cache.putIfAbsent(id, () {
        if (id.isEmpty) return const [''];
        final out = <String>[];
        String? c = id;
        var guard = 0;
        while (c != null && c.isNotEmpty && guard++ < 6) {
          out.insert(0, c);
          c = ctx.categoryOf(c)?.parentId;
        }
        return out.isEmpty ? [id] : out;
      });

  bool under(String txCat, String node) => txCat == node || path(txCat).contains(node);

  /// Direkte Unterkategorie von [node], in die [txCat] fällt (null, wenn [txCat] == [node] oder außerhalb).
  String? childOf(String txCat, String node) {
    final p = path(txCat);
    final i = p.indexOf(node);
    return i >= 0 && i + 1 < p.length ? p[i + 1] : null;
  }

  String name(String id) => id.isEmpty ? 'Unkategorisiert' : (ctx.categoryOf(id)?.name ?? id);
  String? parent(String id) {
    final p = path(id);
    return p.length >= 2 ? p[p.length - 2] : null;
  }
}

String _cat(Transaction t) => t.categoryId ?? '';

/// Umbuchungen zwischen eigenen Konten, Sparpläne und ausgeschlossene Umsätze sind weder Einnahme
/// noch Ausgabe – genau wie in den Auswertungen.
bool _neutral(Transaction t, TxFilterContext ctx) =>
    t.isTransfer || t.excluded || ctx.categoryOf(t.categoryId)?.kind == CategoryKind.umbuchung;

bool isFilterExpense(Transaction t, TxFilterContext ctx) => t.amountCents < 0 && !_neutral(t, ctx);
bool isFilterIncome(Transaction t, TxFilterContext ctx) => t.amountCents > 0 && !_neutral(t, ctx);

class _Match {
  _Match(this.f, this.ctx, this.cats);
  final TxFilter f;
  final TxFilterContext ctx;
  final _Cats cats;

  bool kind(Transaction t) => switch (f.kind) {
        TxKind.all => true,
        TxKind.expenses => isFilterExpense(t, ctx),
        TxKind.income => isFilterIncome(t, ctx),
      };
  bool category(Transaction t) => f.categoryId == null || cats.under(_cat(t), f.categoryId!);
  bool account(Transaction t) => f.accountId == null || t.accountId == f.accountId;
  bool merchant(Transaction t) => f.merchantKey == null || ctx.merchantKey(t) == f.merchantKey;
  bool range(Transaction t) => !f.onlyRange || !t.bookingDate.isBefore(ctx.rangeFrom);

  /// Alle Filter außer den übersprungenen.
  bool all(Transaction t, {bool skipKind = false, bool skipCategory = false, bool skipAccount = false, bool skipMerchant = false, bool skipRange = false}) =>
      (skipKind || kind(t)) &&
      (skipCategory || category(t)) &&
      (skipAccount || account(t)) &&
      (skipMerchant || merchant(t)) &&
      (skipRange || range(t));
}

List<Transaction> _searched(List<Transaction> all, TxFilter f, TxFilterContext ctx) {
  final q = f.query.trim().toLowerCase();
  return q.isEmpty ? all : all.where((t) => ctx.searchText(t).contains(q)).toList();
}

/// Umsätze, die zum Filter passen.
List<Transaction> filterTransactions(List<Transaction> all, TxFilter f, TxFilterContext ctx) {
  final m = _Match(f, ctx, _Cats(ctx));
  return _searched(all, f, ctx).where(m.all).toList();
}

int _absSum(Iterable<Transaction> list) => list.fold<int>(0, (a, t) => a + t.amountCents.abs());

/// Baut die Filterleiste: Das Gewählte steht vorn (Art → Kategorie-Pfad → Konto → Firma → Zeitraum),
/// danach folgen nur Optionen, die mit der aktuellen Auswahl Umsätze liefern **und** die Liste
/// weiter eingrenzen.
FilterBar computeFilterBar(List<Transaction> all, TxFilter f, TxFilterContext ctx) {
  final cats = _Cats(ctx);
  final m = _Match(f, ctx, cats);
  final pool = _searched(all, f, ctx);
  final selected = <FilterChipSpec>[];
  final options = <FilterChipSpec>[];

  // --- Art
  if (f.kind != TxKind.all) {
    final isIncome = f.kind == TxKind.income;
    selected.add(FilterChipSpec(
      dim: FilterDim.kind,
      id: isIncome ? 'income' : 'expenses',
      label: isIncome ? 'Einnahmen' : 'Ausgaben',
      selected: true,
      count: pool.where(m.all).length,
    ));
  } else {
    final base = pool.where((t) => m.all(t, skipKind: true)).toList();
    final exp = base.where((t) => isFilterExpense(t, ctx)).length;
    final inc = base.where((t) => isFilterIncome(t, ctx)).length;
    if (exp > 0 && exp < base.length) options.add(FilterChipSpec(dim: FilterDim.kind, id: 'expenses', label: 'Ausgaben', count: exp));
    if (inc > 0 && inc < base.length) options.add(FilterChipSpec(dim: FilterDim.kind, id: 'income', label: 'Einnahmen', count: inc));
  }

  // --- Kategorie: gewählter Pfad vorn, darunter die noch sinnvollen (Unter-)Kategorien
  final sel = f.categoryId;
  if (sel != null) {
    for (final id in cats.path(sel)) {
      selected.add(FilterChipSpec(dim: FilterDim.category, id: id, label: cats.name(id), selected: true));
    }
  }
  final catBase = pool.where((t) => m.all(t, skipCategory: true)).toList();
  final scope = sel == null ? catBase : catBase.where((t) => cats.under(_cat(t), sel)).toList();
  final groups = <String, List<Transaction>>{};
  if (sel == null) {
    final leaves = {for (final t in scope) _cat(t)};
    final flat = leaves.length <= _flatLimit;
    for (final t in scope) {
      groups.putIfAbsent(flat ? _cat(t) : cats.path(_cat(t)).first, () => []).add(t);
    }
  } else {
    for (final t in scope) {
      final child = cats.childOf(_cat(t), sel);
      if (child != null) groups.putIfAbsent(child, () => []).add(t);
    }
  }
  final catOptions = [
    for (final e in groups.entries)
      if (e.value.length < scope.length) FilterChipSpec(dim: FilterDim.category, id: e.key, label: cats.name(e.key), count: e.value.length),
  ]..sort((a, b) => _absSum(groups[b.id]!).compareTo(_absSum(groups[a.id]!)));
  options.addAll(catOptions);

  // --- Konto (nur bei mehreren Konten)
  if (f.accountId != null) {
    selected.add(FilterChipSpec(dim: FilterDim.account, id: f.accountId!, label: ctx.accountName(f.accountId!), selected: true));
  } else if (ctx.accountCount >= 2) {
    final base = pool.where((t) => m.all(t, skipAccount: true)).toList();
    final byAccount = <String, int>{};
    for (final t in base) {
      byAccount[t.accountId] = (byAccount[t.accountId] ?? 0) + 1;
    }
    for (final e in (byAccount.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) {
      if (e.value < base.length) options.add(FilterChipSpec(dim: FilterDim.account, id: e.key, label: ctx.accountName(e.key), count: e.value));
    }
  }

  // --- Firma (erst wenn Art oder Kategorie eingegrenzt sind, sonst wären es zu viele)
  if (f.merchantKey != null) {
    selected.add(FilterChipSpec(dim: FilterDim.merchant, id: f.merchantKey!, label: f.merchantName ?? f.merchantKey!, selected: true));
  } else if (f.kind != TxKind.all || f.categoryId != null) {
    final base = pool.where((t) => m.all(t, skipMerchant: true)).toList();
    final byMerchant = <String, List<Transaction>>{};
    for (final t in base) {
      byMerchant.putIfAbsent(ctx.merchantKey(t), () => []).add(t);
    }
    final ranked = byMerchant.entries.where((e) => e.value.length < base.length).toList()
      ..sort((a, b) => _absSum(b.value).compareTo(_absSum(a.value)));
    for (final e in ranked.take(_merchantLimit)) {
      options.add(FilterChipSpec(dim: FilterDim.merchant, id: e.key, label: ctx.merchantName(e.value.first), count: e.value.length));
    }
  }

  // --- Zeitraum
  if (f.onlyRange) {
    selected.add(FilterChipSpec(dim: FilterDim.range, id: 'range', label: ctx.rangeLabel, selected: true));
  } else {
    final base = pool.where((t) => m.all(t, skipRange: true)).toList();
    final inRange = base.where((t) => !t.bookingDate.isBefore(ctx.rangeFrom)).length;
    if (inRange > 0 && inRange < base.length) options.add(FilterChipSpec(dim: FilterDim.range, id: 'range', label: ctx.rangeLabel, count: inRange));
  }

  return FilterBar(selected: selected, options: options);
}

/// Wendet einen Tipp auf einen Chip an.
///
/// - Eine Option wählen: Art und Konto/Zeitraum werden gesetzt; eine Kategorie ersetzt die bisherige
///   Auswahl derselben Ebene, die Firma darunter wird zurückgesetzt.
/// - Etwas Gewähltes abwählen: alles **darunter** wird ebenfalls abgewählt (Art → Kategorien → Firma;
///   eine Oberkategorie nimmt ihre Unterkategorie mit). Konto und Zeitraum sind unabhängig.
TxFilter applyChip(TxFilter f, FilterChipSpec chip, TxFilterContext ctx) {
  switch (chip.dim) {
    case FilterDim.kind:
      if (chip.selected) {
        return f.copyWith(kind: TxKind.all, categoryId: null, merchantKey: null, merchantName: null);
      }
      return f.copyWith(kind: chip.id == 'income' ? TxKind.income : TxKind.expenses);
    case FilterDim.category:
      if (chip.selected) {
        // Eine Ebene höher; bei der Oberkategorie ganz ohne Kategorie.
        final parent = _Cats(ctx).parent(chip.id);
        return f.copyWith(categoryId: parent, merchantKey: null, merchantName: null);
      }
      return f.copyWith(categoryId: chip.id, merchantKey: null, merchantName: null);
    case FilterDim.account:
      return f.copyWith(accountId: chip.selected ? null : chip.id);
    case FilterDim.merchant:
      return chip.selected ? f.copyWith(merchantKey: null, merchantName: null) : f.copyWith(merchantKey: chip.id, merchantName: chip.label);
    case FilterDim.range:
      return f.copyWith(onlyRange: !chip.selected);
  }
}
