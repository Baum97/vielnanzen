import 'dart:convert';
import 'dart:io';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'secure_key.dart';

/// Verschlüsselte, rein lokale Persistenz aller App-Daten.
/// Datei: AES-256-GCM-verschlüsseltes JSON im App-Dokumentenverzeichnis.
/// Schnittstelle für eine spätere SQLCipher/drift-Anbindung bleibt offen.
class Store extends ChangeNotifier {
  Store({SecureKeyStore? keyStore}) : _keyStore = keyStore ?? LocalSecureKeyStore();

  final SecureKeyStore _keyStore;

  enc.Encrypter? _encrypter;
  File? _file;

  final List<Account> accounts = [];
  final List<Transaction> transactions = [];
  final List<Merchant> merchants = [];
  final List<Contract> contracts = [];
  final List<Rule> rules = [];
  final List<Budget> budgets = [];
  final List<Goal> goals = [];
  final List<Insight> insights = [];
  final List<NetworkLogEntry> networkLog = [];
  final List<BankConnection> connections = [];

  final Map<String, dynamic> settings = {
    'discreetMode': false,
    'darkMode': 'system',
    'accentColor': '#2F5BEA',
    'monthStart': '1',
    'refreshOnOpen': true,
    'notifications': true,
    'appLock': true,
    'hideInSwitcher': true,
    'selectedAccountIds': <String>[],
  };

  bool _loaded = false;
  bool get isLoaded => _loaded;
  void forceLoadedForTest() => _loaded = true;

  Future<void> load() async {
    if (_loaded) return;
    final key = await _keyStore.getOrCreateDatabaseKey();
    final derived = LocalSecureKeyStore.deriveKey(key);
    _encrypter = enc.Encrypter(enc.AES(enc.Key(derived), mode: enc.AESMode.gcm));
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/klarblick.db.enc');
    if (await _file!.exists()) {
      try {
        final iv = enc.IV(derived.sublist(0, 12));
        final encrypted = enc.Encrypted.fromBase64(await _file!.readAsString());
        final plain = _encrypter!.decrypt(encrypted, iv: iv);
        _applyJson(jsonDecode(plain) as Map<String, dynamic>);
      } catch (_) {
        // Datei beschädigt – starte leer, Daten bleiben lokal erhalten wo möglich.
      }
    }
    _loaded = true;
    notifyListeners();
  }

  void _applyJson(Map<String, dynamic> j) {
    accounts
      ..clear()
      ..addAll((j['accounts'] as List? ?? []).map((e) => Account.fromJson(e as Map<String, dynamic>)));
    transactions
      ..clear()
      ..addAll((j['transactions'] as List? ?? []).map((e) => Transaction.fromJson(e as Map<String, dynamic>)));
    merchants
      ..clear()
      ..addAll((j['merchants'] as List? ?? []).map((e) => Merchant(
            id: e['id'] as String,
            normalizedName: e['normalizedName'] as String,
            displayName: e['displayName'] as String,
            defaultCategoryId: e['defaultCategoryId'] as String?,
          )));
    contracts
      ..clear()
      ..addAll((j['contracts'] as List? ?? []).map((e) => Contract.fromJson(e as Map<String, dynamic>)));
    rules
      ..clear()
      ..addAll((j['rules'] as List? ?? []).map((e) => Rule.fromJson(e as Map<String, dynamic>)));
    budgets
      ..clear()
      ..addAll((j['budgets'] as List? ?? []).map((e) => Budget.fromJson(e as Map<String, dynamic>)));
    goals
      ..clear()
      ..addAll((j['goals'] as List? ?? []).map((e) => Goal.fromJson(e as Map<String, dynamic>)));
    insights
      ..clear()
      ..addAll((j['insights'] as List? ?? []).map((e) => Insight.fromJson(e as Map<String, dynamic?)));
    networkLog
      ..clear()
      ..addAll((j['networkLog'] as List? ?? []).map((e) => NetworkLogEntry.fromJson(e as Map<String, dynamic>)));
    connections
      ..clear()
      ..addAll((j['connections'] as List? ?? []).map((e) => BankConnection.fromJson(e as Map<String, dynamic?)));
    final s = j['settings'] as Map<String, dynamic>?;
    if (s != null) settings.addAll(s);
  }

  Map<String, dynamic> _toJson() => {
        'version': 1,
        'accounts': accounts.map((e) => e.toJson()).toList(),
        'transactions': transactions.map((e) => e.toJson()).toList(),
        'merchants': merchants
            .map((m) => {'id': m.id, 'normalizedName': m.normalizedName, 'displayName': m.displayName, 'defaultCategoryId': m.defaultCategoryId})
            .toList(),
        'contracts': contracts.map((e) => e.toJson()).toList(),
        'rules': rules.map((e) => e.toJson()).toList(),
        'budgets': budgets.map((e) => e.toJson()).toList(),
        'goals': goals.map((e) => e.toJson()).toList(),
        'insights': insights.map((e) => e.toJson()).toList(),
        'networkLog': networkLog.map((e) => e.toJson()).toList(),
        'connections': connections.map((e) => e.toJson()).toList(),
        'settings': settings,
      };

  Future<void> save() async {
    if (_encrypter == null || _file == null) return;
    final key = await _keyStore.getOrCreateDatabaseKey();
    final derived = LocalSecureKeyStore.deriveKey(key);
    final iv = enc.IV(derived.sublist(0, 12));
    final encrypted = _encrypter!.encrypt(jsonEncode(_toJson()), iv: iv);
    await _file!.writeAsString(encrypted.base64);
  }

  void updateSettings(Map<String, dynamic> patch) {
    settings.addAll(patch);
    notifyListeners();
    save();
  }

  void addNetworkLog(String host, String purpose) {
    networkLog.insert(
      0,
      NetworkLogEntry(id: DateTime.now().microsecondsSinceEpoch.toString(), host: host, timestamp: DateTime.now(), purpose: purpose),
    );
    if (networkLog.length > 500) networkLog.removeLast();
    save();
  }

  void upsertAccount(Account a) {
    final i = accounts.indexWhere((e) => e.id == a.id);
    if (i >= 0) {
      accounts[i] = a;
    } else {
      accounts.add(a);
    }
    notifyListeners();
    save();
  }

  void removeAccount(String id) {
    accounts.removeWhere((e) => e.id == id);
    transactions.removeWhere((t) => t.accountId == id);
    notifyListeners();
    save();
  }

  void upsertTransactions(List<Transaction> list) {
    for (final t in list) {
      final i = transactions.indexWhere((e) => e.dedupHash == t.dedupHash);
      if (i >= 0) {
        transactions[i] = t.copyWith(categoryId: transactions[i].categoryId, excluded: transactions[i].excluded, note: transactions[i].note, tags: transactions[i].tags);
      } else {
        transactions.add(t);
      }
    }
    notifyListeners();
    save();
  }

  void upsertTransaction(Transaction t) {
    final i = transactions.indexWhere((e) => e.id == t.id);
    if (i >= 0) {
      transactions[i] = t;
    } else {
      transactions.add(t);
    }
    notifyListeners();
    save();
  }

  void upsertContract(Contract c) {
    final i = contracts.indexWhere((e) => e.id == c.id);
    if (i >= 0) {
      contracts[i] = c;
    } else {
      contracts.add(c);
    }
    notifyListeners();
    save();
  }

  void removeContract(String id) {
    contracts.removeWhere((e) => e.id == id);
    notifyListeners();
    save();
  }

  void upsertRule(Rule r) {
    final i = rules.indexWhere((e) == e.id == r.id);
    if (i >= 0) {
      rules[i] = r;
    } else {
      rules.add(r);
    }
    notifyListeners();
    save();
  }

  void removeRule(String id) {
    rules.removeWhere((e) == e.id == id);
    notifyListeners();
    save();
  }

  void upsertBudget(Budget b) {
    final i = budgets.indexWhere((e) => e.id == b.id);
    if (i >= 0) {
      budgets[i] = b;
    } else {
      budgets.add(b);
    }
    notifyListeners();
    save();
  }

  void upsertGoal(Goal g) {
    final i = goals.indexWhere((e) == g.id == g.id);
    if (i >= 0) {
      goals[i] = g;
    } else {
      goals.add(g);
    }
    notifyListeners();
    save();
  }

  void upsertInsight(Insight i) {
    final idx = insights.indexWhere((e) => e.id == i.id);
    if (idx >= 0) {
      insights[idx] = i;
    } else {
      insights.add(i);
    }
    notifyListeners();
    save();
  }

  void dismissInsight(String id) {
    final i = insights.indexWhere((e) => e.id == id);
    if (i >= 0) {
      insights[i] = Insight(
        id: insights[i].id,
        type: insights[i].type,
        title: insights[i].title,
        detail: insights[i].detail,
        potentialCentsPerYear: insights[i].potentialCentsPerYear,
        createdAt: insights[i].createdAt,
        dismissedAt: DateTime.now(),
        payloadJson: insights[i].payloadJson,
      );
      notifyListeners();
      save();
    }
  }

  void upsertMerchant(Merchant m) {
    final i = merchants.indexWhere((e) == e.normalizedName == m.normalizedName);
    if (i >= 0) {
      merchants[i] = m;
    } else {
      merchants.add(m);
    }
    notifyListeners();
    save();
  }

  void upsertConnection(BankConnection c) {
    final i = connections.indexWhere((e) == e.id == c.id);
    if (i >= 0) {
      connections[i] = c;
    } else {
      connections.add(c);
    }
    notifyListeners();
    save();
  }

  List<Transaction> transactionsForAccounts(Set<String> accountIds) =>
      transactions.where((t) => accountIds.isEmpty || accountIds.contains(t.accountId)).toList()
        ..sort((a, b) => b.bookingDate.compareTo(a.bookingDate));
}
