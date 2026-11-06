import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'blob/blob_storage.dart';
import 'models.dart';
import 'secure_key.dart';

/// Verschlüsselte, rein lokale Persistenz aller App-Daten.
///
/// Format v2: `KB2:` + Base64(Nonce[12] ‖ Chiffrat ‖ GCM-Tag[16]), AES-256-GCM
/// mit **zufälligem Nonce pro Speichervorgang**. Version 1.0 nutzte einen festen
/// IV; solche Container werden noch gelesen und beim nächsten Speichern ersetzt.
class Store extends ChangeNotifier {
  Store({SecureKeyStore? keyStore, BlobStorage? blob})
      : keyStore = keyStore ?? DeviceSecureKeyStore(),
        _blob = blob ?? BlobStorage.platform();

  final SecureKeyStore keyStore;
  final BlobStorage _blob;
  static final _cipher = AesGcm.with256bits();
  static const _prefix = 'KB2:';

  SecretKey? _key;
  Uint8List? _legacyIv;

  final List<Account> accounts = [];
  final List<Transaction> transactions = [];
  final List<Contract> contracts = [];
  final List<Rule> rules = [];
  final List<Budget> budgets = [];
  final List<Goal> goals = [];
  final List<Insight> insights = [];
  final List<NetworkLogEntry> networkLog = [];
  final List<BankConnection> connections = [];

  final Map<String, int> _byHash = {};

  static Map<String, dynamic> defaultSettings() => {
        'discreetMode': false,
        'darkMode': 'system',
        'refreshOnOpen': false,
        'appLock': false,
        'timeRange': 'm1',
        'fintsProductId': '',
      };

  final Map<String, dynamic> settings = defaultSettings();

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Für Tests: ohne Plattformkanäle als geladen markieren.
  @visibleForTesting
  void forceLoadedForTest() => _loaded = true;

  String? loadError;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await keyStore.getOrCreateDatabaseKey();
      final derived = deriveDatabaseKey(raw);
      _key = SecretKey(derived);
      _legacyIv = derived.sublist(0, 12);
      final data = await _blob.read();
      if (data != null && data.isNotEmpty) {
        try {
          _applyJson(jsonDecode(await _decrypt(data)) as Map<String, dynamic>);
        } catch (e) {
          // Nicht lesbar: Container sichern statt überschreiben und leer starten.
          loadError = 'Gespeicherte Daten konnten nicht entschlüsselt werden. Eine Sicherung wurde angelegt.';
          await _blob.backupCorrupt(data);
        }
      }
    } catch (e) {
      loadError = 'Speicher nicht verfügbar: $e';
    }
    _loaded = true;
    notifyListeners();
  }

  Future<String> _decrypt(String data) async {
    if (data.startsWith(_prefix)) {
      final bytes = base64Decode(data.substring(_prefix.length));
      final box = SecretBox.fromConcatenation(bytes, nonceLength: 12, macLength: 16);
      return utf8.decode(await _cipher.decrypt(box, secretKey: _key!));
    }
    // Legacy v1: Base64(Chiffrat ‖ Tag) mit festem IV
    final bytes = base64Decode(data);
    final box = SecretBox(
      bytes.sublist(0, bytes.length - 16),
      nonce: _legacyIv!,
      mac: Mac(bytes.sublist(bytes.length - 16)),
    );
    return utf8.decode(await _cipher.decrypt(box, secretKey: _key!));
  }

  Future<String> _encrypt(String plain) async {
    final box = await _cipher.encrypt(utf8.encode(plain), secretKey: _key!, nonce: _cipher.newNonce());
    return _prefix + base64Encode(box.concatenation());
  }

  void _applyJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) =>
        (j[key] as List? ?? []).map((e) => f(e as Map<String, dynamic>)).toList();
    accounts
      ..clear()
      ..addAll(list('accounts', Account.fromJson));
    transactions
      ..clear()
      ..addAll(list('transactions', Transaction.fromJson));
    contracts
      ..clear()
      ..addAll(list('contracts', Contract.fromJson));
    rules
      ..clear()
      ..addAll(list('rules', Rule.fromJson));
    budgets
      ..clear()
      ..addAll(list('budgets', Budget.fromJson));
    goals
      ..clear()
      ..addAll(list('goals', Goal.fromJson));
    insights
      ..clear()
      ..addAll(list('insights', Insight.fromJson));
    networkLog
      ..clear()
      ..addAll(list('networkLog', NetworkLogEntry.fromJson));
    connections
      ..clear()
      ..addAll(list('connections', BankConnection.fromJson));
    final s = j['settings'] as Map<String, dynamic>?;
    if (s != null) settings.addAll(s);
    _reindex();
  }

  Map<String, dynamic> toJson() => {
        'version': 2,
        'accounts': accounts.map((e) => e.toJson()).toList(),
        'transactions': transactions.map((e) => e.toJson()).toList(),
        'contracts': contracts.map((e) => e.toJson()).toList(),
        'rules': rules.map((e) => e.toJson()).toList(),
        'budgets': budgets.map((e) => e.toJson()).toList(),
        'goals': goals.map((e) => e.toJson()).toList(),
        'insights': insights.map((e) => e.toJson()).toList(),
        'networkLog': networkLog.map((e) => e.toJson()).toList(),
        'connections': connections.map((e) => e.toJson()).toList(),
        'settings': settings,
      };

  // ---------------------------------------------------------------------------
  // Speichern (entprellt) & Benachrichtigen

  Timer? _saveTimer;
  Future<void>? _saving;
  bool _dirty = false;
  int _batchDepth = 0;
  bool _pendingNotify = false;

  void _changed() {
    if (_batchDepth > 0) {
      _pendingNotify = true;
      return;
    }
    notifyListeners();
    _scheduleSave();
  }

  /// Mehrere Änderungen zusammenfassen: eine Benachrichtigung, ein Speichervorgang.
  void batch(void Function() fn) {
    _batchDepth++;
    try {
      fn();
    } finally {
      _batchDepth--;
      if (_batchDepth == 0 && _pendingNotify) {
        _pendingNotify = false;
        _changed();
      }
    }
  }

  void _scheduleSave() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () => save());
  }

  /// Schreibt sofort (z. B. bevor die App in den Hintergrund geht).
  Future<void> save() async {
    _saveTimer?.cancel();
    if (_key == null) return;
    if (_saving != null) {
      await _saving;
      if (!_dirty) return;
    }
    _dirty = false;
    final completer = Completer<void>();
    _saving = completer.future;
    try {
      await _blob.write(await _encrypt(jsonEncode(toJson())));
    } catch (e) {
      _dirty = true;
      debugPrint('Speichern fehlgeschlagen: $e');
    } finally {
      _saving = null;
      completer.complete();
    }
  }

  // ---------------------------------------------------------------------------
  // Mutationen

  void updateSettings(Map<String, dynamic> patch) {
    settings.addAll(patch);
    _changed();
  }

  void addNetworkLog(String host, String purpose) {
    networkLog.insert(
      0,
      NetworkLogEntry(id: DateTime.now().microsecondsSinceEpoch.toString(), host: host, timestamp: DateTime.now(), purpose: purpose),
    );
    if (networkLog.length > 500) networkLog.removeRange(500, networkLog.length);
    _changed();
  }

  Account? accountById(String id) => accounts.where((a) => a.id == id).firstOrNull;

  void upsertAccount(Account a) {
    final i = accounts.indexWhere((e) => e.id == a.id);
    if (i >= 0) {
      accounts[i] = a;
    } else {
      accounts.add(a);
    }
    _changed();
  }

  void removeAccount(String id) {
    final acc = accountById(id);
    accounts.removeWhere((e) => e.id == id);
    transactions.removeWhere((t) => t.accountId == id);
    if (acc?.connectionId != null && !accounts.any((a) => a.connectionId == acc!.connectionId)) {
      connections.removeWhere((c) => c.id == acc!.connectionId);
    }
    _reindex();
    _changed();
  }

  void _reindex() {
    _byHash.clear();
    for (var i = 0; i < transactions.length; i++) {
      _byHash[transactions[i].dedupHash] = i;
    }
  }

  bool hasTransactionHash(String hash) => _byHash.containsKey(hash);

  /// Fügt neue Umsätze hinzu bzw. aktualisiert vorhandene (gleicher Dedup-Hash).
  /// Nutzerangaben (Kategorie, Notiz, Ausschluss …) bleiben erhalten.
  /// Gibt die Zahl neu hinzugefügter Umsätze zurück.
  int upsertTransactions(List<Transaction> list) {
    var added = 0;
    for (final t in list) {
      final i = _byHash[t.dedupHash];
      if (i != null) {
        final old = transactions[i];
        transactions[i] = old.manualCategory
            ? t.copyWith(
                categoryId: old.categoryId,
                manualCategory: true,
                categoryReason: old.categoryReason,
                excluded: old.excluded,
                isTransfer: old.isTransfer,
                note: old.note,
                tags: old.tags,
              )
            : t.copyWith(excluded: old.excluded, note: old.note, tags: old.tags, isTransfer: old.isTransfer || t.isTransfer);
      } else {
        _byHash[t.dedupHash] = transactions.length;
        transactions.add(t);
        added++;
      }
    }
    _changed();
    return added;
  }

  /// Ersetzt die Analyse-Felder aller Umsätze in einem Rutsch (ohne Reindex).
  void replaceAnalyzedTransactions(List<Transaction> analyzed) {
    if (analyzed.length != transactions.length) {
      transactions
        ..clear()
        ..addAll(analyzed);
      _reindex();
    } else {
      for (var i = 0; i < analyzed.length; i++) {
        transactions[i] = analyzed[i];
      }
    }
    _changed();
  }

  void upsertTransaction(Transaction t) {
    final i = transactions.indexWhere((e) => e.id == t.id);
    if (i >= 0) {
      transactions[i] = t;
    } else {
      _byHash[t.dedupHash] = transactions.length;
      transactions.add(t);
    }
    _changed();
  }

  Transaction? transactionById(String id) => transactions.where((t) => t.id == id).firstOrNull;

  Contract? contractById(String id) => contracts.where((c) => c.id == id).firstOrNull;

  void upsertContract(Contract c) {
    final i = contracts.indexWhere((e) => e.id == c.id);
    if (i >= 0) {
      contracts[i] = c;
    } else {
      contracts.add(c);
    }
    _changed();
  }

  void setContractStatus(String id, ContractStatus status) {
    final c = contractById(id);
    if (c == null) return;
    upsertContract(c.copyWith(status: status, userConfirmed: true));
  }

  void removeContract(String id) {
    contracts.removeWhere((e) => e.id == id);
    _changed();
  }

  void upsertRule(Rule r) {
    final i = rules.indexWhere((e) => e.id == r.id);
    if (i >= 0) {
      rules[i] = r;
    } else {
      rules.add(r);
    }
    _changed();
  }

  void removeRule(String id) {
    rules.removeWhere((e) => e.id == id);
    _changed();
  }

  void upsertBudget(Budget b) {
    final i = budgets.indexWhere((e) => e.id == b.id);
    if (i >= 0) {
      budgets[i] = b;
    } else {
      budgets.add(b);
    }
    _changed();
  }

  void removeBudget(String id) {
    budgets.removeWhere((e) => e.id == id);
    _changed();
  }

  void upsertGoal(Goal g) {
    final i = goals.indexWhere((e) => e.id == g.id);
    if (i >= 0) {
      goals[i] = g;
    } else {
      goals.add(g);
    }
    _changed();
  }

  /// Übernimmt die aktuellen Insights der Analyse; ausgeblendete bleiben ausgeblendet.
  void replaceInsights(List<Insight> fresh) {
    final dismissed = {for (final i in insights.where((i) => i.dismissed)) i.id: i};
    final previous = {for (final i in insights) i.id: i};
    insights
      ..clear()
      ..addAll(fresh.map((i) {
        final d = dismissed[i.id];
        if (d != null) return i.copyWith(dismissedAt: d.dismissedAt);
        final p = previous[i.id];
        return p != null ? i.copyWith(createdAt: p.createdAt) : i;
      }));
    // Ausgeblendete, die gerade nicht auftreten, merken (sonst kämen sie zurück).
    for (final d in dismissed.values) {
      if (!insights.any((i) => i.id == d.id)) insights.add(d);
    }
    _changed();
  }

  void dismissInsight(String id) {
    final i = insights.indexWhere((e) => e.id == id);
    if (i >= 0) {
      insights[i] = insights[i].copyWith(dismissedAt: DateTime.now());
      _changed();
    }
  }

  void restoreInsights() {
    for (var i = 0; i < insights.length; i++) {
      if (insights[i].dismissed) {
        final x = insights[i];
        insights[i] = Insight(
          id: x.id,
          type: x.type,
          title: x.title,
          detail: x.detail,
          action: x.action,
          potentialCentsPerYear: x.potentialCentsPerYear,
          createdAt: x.createdAt,
          contractId: x.contractId,
          merchantName: x.merchantName,
          categoryId: x.categoryId,
        );
      }
    }
    _changed();
  }

  BankConnection? connectionById(String id) => connections.where((c) => c.id == id).firstOrNull;

  static String pinKeyFor(String connectionId) => 'klarblick.pin.$connectionId';

  void upsertConnection(BankConnection c) {
    final i = connections.indexWhere((e) => e.id == c.id);
    if (i >= 0) {
      connections[i] = c;
    } else {
      connections.add(c);
    }
    _changed();
  }

  /// Löscht alle Daten inkl. Schlüssel und gespeicherter PINs.
  Future<void> wipe() async {
    for (final c in connections) {
      try {
        await keyStore.write(pinKeyFor(c.id), null);
      } catch (_) {}
    }
    accounts.clear();
    transactions.clear();
    contracts.clear();
    rules.clear();
    budgets.clear();
    goals.clear();
    insights.clear();
    networkLog.clear();
    connections.clear();
    settings
      ..clear()
      ..addAll(defaultSettings());
    _reindex();
    _saveTimer?.cancel();
    await _blob.delete();
    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
