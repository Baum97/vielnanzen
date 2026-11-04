/// Kern-Datenmodell von Klarblick.
/// Alle Beträge werden als Ganzzahl in Cent gespeichert (nie Gleitkomma).
library;

enum AccountType { giro, kreditkarte, tagesgeld, bargeld, manual }

enum CategoryKind { ausgabe, einnahme, umbuchung }

enum ContractStatus { vorschlag, aktiv, gekuendigt, beendet, ignoriert }

enum ContractInterval { woechentlich, zweiwoechentlich, monatlich, quartalsweise, halbjahrlich, jaehrlich, individuell }

enum InsightType {
  preiserhoehung,
  doppelteDienst,
  bankgebuehren,
  kategorieAuffaellig,
  doppelteAbbuchung,
  trotzKuendigung,
  verguenstigeresAngebot,
  hoehererGiroSaldo,
}

class Category {
  final String id;
  final String? parentId;
  final String name;
  final String icon;
  final String color;
  final CategoryKind kind;

  const Category({
    required this.id,
    this.parentId,
    required this.name,
    required this.icon,
    required this.color,
    required this.kind,
  });

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as String,
        parentId: j['parentId'] as String?,
        name: j['name'] as String,
        icon: j['icon'] as String,
        color: j['color'] as String,
        kind: CategoryKind.values.firstWhere(
          (k) => k.name == (j['kind'] as String).toLowerCase(),
          orElse: () => CategoryKind.ausgabe,
        ),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'parentId': parentId,
        'name': name,
        'icon': icon,
        'color': color,
        'kind': kind.name,
      };
}

class Merchant {
  final String id;
  final String normalizedName;
  final String displayName;
  final String? defaultCategoryId;

  const Merchant({
    required this.id,
    required this.normalizedName,
    required this.displayName,
    this.defaultCategoryId,
  });

  String get monogram {
    final letters = displayName.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '').trim();
    if (letters.isEmpty) return '?';
    final parts = letters.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return letters.substring(0, letters.length >= 2 ? 2 : 1).toUpperCase();
  }
}

class Account {
  final String id;
  final String? connectionId;
  final String iban;
  final String name;
  final AccountType type;
  final String currency;
  final int balanceCents;
  final DateTime? balanceDate;
  final String color;
  final bool hidden;
  final bool includeInTotal;

  const Account({
    required this.id,
    this.connectionId,
    required this.iban,
    required this.name,
    required this.type,
    this.currency = 'EUR',
    this.balanceCents = 0,
    this.balanceDate,
    this.color = '#2F5BEA',
    this.hidden = false,
    this.includeInTotal = true,
  });

  Account copyWith({
    String? name,
    int? balanceCents,
    DateTime? balanceDate,
    String? color,
    bool? hidden,
    bool? includeInTotal,
  }) =>
      Account(
        id: id,
        connectionId: connectionId,
        iban: iban,
        name: name ?? this.name,
        type: type,
        currency: currency,
        balanceCents: balanceCents ?? this.balanceCents,
        balanceDate: balanceDate ?? this.balanceDate,
        color: color ?? this.color,
        hidden: hidden ?? this.hidden,
        includeInTotal: includeInTotal ?? this.includeInTotal,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'connectionId': connectionId,
        'iban': iban,
        'name': name,
        'type': type.name,
        'currency': currency,
        'balanceCents': balanceCents,
        'balanceDate': balanceDate?.toIso8601String(),
        'color': color,
        'hidden': hidden,
        'includeInTotal': includeInTotal,
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        connectionId: j['connectionId'] as String?,
        iban: j['iban'] as String,
        name: j['name'] as String,
        type: AccountType.values.firstWhere((t) => t.name == j['type'], orElse: () => AccountType.manual),
        currency: j['currency'] as String? ?? 'EUR',
        balanceCents: (j['balanceCents'] as num).toInt(),
        balanceDate: j['balanceDate'] != null ? DateTime.parse(j['balanceDate'] as String) : null,
        color: j['color'] as String? ?? '#2F5BEA',
        hidden: j['hidden'] as bool? ?? false,
        includeInTotal: j['includeInTotal'] as bool? ?? true,
      );
}

class Transaction {
  final String id;
  final String accountId;
  final DateTime bookingDate;
  final DateTime? valueDate;
  final int amountCents;
  final String counterpartyName;
  final String? counterpartyIban;
  final String purpose;
  final String? mandateRef;
  final String? creditorId;
  final String? endToEndRef;
  final String? gvc;
  final bool pending;
  final String dedupHash;
  final String? categoryId;
  final String? merchantId;
  final String? contractId;
  final bool isTransfer;
  final bool excluded;
  final String? note;
  final List<String> tags;
  final String? categoryReason;

  const Transaction({
    required this.id,
    required this.accountId,
    required this.bookingDate,
    this.valueDate,
    required this.amountCents,
    required this.counterpartyName,
    this.counterpartyIban,
    this.purpose = '',
    this.mandateRef,
    this.creditorId,
    this.endToEndRef,
    this.gvc,
    this.pending = false,
    required this.dedupHash,
    this.categoryId,
    this.merchantId,
    this.contractId,
    this.isTransfer = false,
    this.excluded = false,
    this.note,
    this.tags = const [],
    this.categoryReason,
  });

  bool get isIncome => amountCents > 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountId': accountId,
        'bookingDate': bookingDate.toIso8601String(),
        'valueDate': valueDate?.toIso8601String(),
        'amountCents': amountCents,
        'counterpartyName': counterpartyName,
        'counterpartyIban': counterpartyIban,
        'purpose': purpose,
        'mandateRef': mandateRef,
        'creditorId': creditorId,
        'endToEndRef': endToEndRef,
        'gvc': gvc,
        'pending': pending,
        'dedupHash': dedupHash,
        'categoryId': categoryId,
        'merchantId': merchantId,
        'contractId': contractId,
        'isTransfer': isTransfer,
        'excluded': excluded,
        'note': note,
        'tags': tags,
        'categoryReason': categoryReason,
      };

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: j['id'] as String,
        accountId: j['accountId'] as String,
        bookingDate: DateTime.parse(j['bookingDate'] as String),
        valueDate: j['valueDate'] != null ? DateTime.parse(j['valueDate'] as String) : null,
        amountCents: (j['amountCents'] as num).toInt(),
        counterpartyName: j['counterpartyName'] as String,
        counterpartyIban: j['counterpartyIban'] as String?,
        purpose: j['purpose'] as String? ?? '',
        mandateRef: j['mandateRef'] as String?,
        creditorId: j['creditorId'] as String?,
        endToEndRef: j['endToEndRef'] as String?,
        gvc: j['gvc'] as String?,
        pending: j['pending'] as bool? ?? false,
        dedupHash: j['dedupHash'] as String,
        categoryId: j['categoryId'] as String?,
        merchantId: j['merchantId'] as String?,
        contractId: j['contractId'] as String?,
        isTransfer: j['isTransfer'] as bool? ?? false,
        excluded: j['excluded'] as bool? ?? false,
        note: j['note'] as String?,
        tags: (j['tags'] as List?)?.map((e) => e as String).toList() ?? const [],
        categoryReason: j['categoryReason'] as String?,
      );

  Transaction copyWith({
    String? categoryId,
    String? merchantId,
    String? contractId,
    bool? isTransfer,
    bool? excluded,
    bool? pending,
    String? note,
    List<String>? tags,
    String? categoryReason,
  }) =>
      Transaction(
        id: id,
        accountId: accountId,
        bookingDate: bookingDate,
        valueDate: valueDate,
        amountCents: amountCents,
        counterpartyName: counterpartyName,
        counterpartyIban: counterpartyIban,
        purpose: purpose,
        mandateRef: mandateRef,
        creditorId: creditorId,
        endToEndRef: endToEndRef,
        gvc: gvc,
        pending: pending ?? this.pending,
        dedupHash: dedupHash,
        categoryId: categoryId ?? this.categoryId,
        merchantId: merchantId ?? this.merchantId,
        contractId: contractId ?? this.contractId,
        isTransfer: isTransfer ?? this.isTransfer,
        excluded: excluded ?? this.excluded,
        note: note ?? this.note,
        tags: tags ?? this.tags,
        categoryReason: categoryReason ?? this.categoryReason,
      );
}

class Contract {
  final String id;
  final String? merchantId;
  final String name;
  final ContractInterval interval;
  final int expectedCents;
  final DateTime? nextDue;
  final double confidence;
  final ContractStatus status;
  final String? noticePeriod;
  final DateTime? minTermEnd;
  final String? reminder;
  final String? categoryId;
  final String? accountId;
  final String? reason;
  final List<String> transactionIds;

  const Contract({
    required this.id,
    this.merchantId,
    required this.name,
    required this.interval,
    required this.expectedCents,
    this.nextDue,
    this.confidence = 0,
    this.status = ContractStatus.vorschlag,
    this.noticePeriod,
    this.minTermEnd,
    this.reminder,
    this.categoryId,
    this.accountId,
    this.reason,
    this.transactionIds = const [],
  });

  double get monthlyCents {
    switch (interval) {
      case ContractInterval.woechentlich:
        return expectedCents * 52 / 12;
      case ContractInterval.zweiwoechentlich:
        return expectedCents * 26 / 12;
      case ContractInterval.monatlich:
        return expectedCents.toDouble();
      case ContractInterval.quartalsweise:
        return expectedCents / 3;
      case ContractInterval.halbjahrlich:
        return expectedCents / 6;
      case ContractInterval.jaehrlich:
        return expectedCents / 12;
      case ContractInterval.individuell:
        return expectedCents.toDouble();
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'merchantId': merchantId,
        'name': name,
        'interval': interval.name,
        'expectedCents': expectedCents,
        'nextDue': nextDue?.toIso8601String(),
        'confidence': confidence,
        'status': status.name,
        'noticePeriod': noticePeriod,
        'minTermEnd': minTermEnd?.toIso8601String(),
        'reminder': reminder,
        'categoryId': categoryId,
        'accountId': accountId,
        'reason': reason,
        'transactionIds': transactionIds,
      };

  factory Contract.fromJson(Map<String, dynamic> j) => Contract(
        id: j['id'] as String,
        merchantId: j['merchantId'] as String?,
        name: j['name'] as String,
        interval: ContractInterval.values.firstWhere((i) => i.name == j['interval'], orElse: () => ContractInterval.monatlich),
        expectedCents: (j['expectedCents'] as num).toInt(),
        nextDue: j['nextDue'] != null ? DateTime.parse(j['nextDue'] as String) : null,
        confidence: (j['confidence'] as num).toDouble(),
        status: ContractStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => ContractStatus.vorschlag),
        noticePeriod: j['noticePeriod'] as String?,
        minTermEnd: j['minTermEnd'] != null ? DateTime.parse(j['minTermEnd'] as String) : null,
        reminder: j['reminder'] as String?,
        categoryId: j['categoryId'] as String?,
        accountId: j['accountId'] as String?,
        reason: j['reason'] as String?,
        transactionIds: (j['transactionIds'] as List?)?.map((e) => e as String).toList() ?? const [],
      );
}

class Rule {
  final String id;
  final String field;
  final String operator;
  final String value;
  final String action;
  final String actionValue;
  final int priority;

  const Rule({
    required this.id,
    required this.field,
    required this.operator,
    required this.value,
    required this.action,
    required this.actionValue,
    this.priority = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'field': field,
        'operator': operator,
        'value': value,
        'action': action,
        'actionValue': actionValue,
        'priority': priority,
      };

  factory Rule.fromJson(Map<String, dynamic> j) => Rule(
        id: j['id'] as String,
        field: j['field'] as String,
        operator: j['operator'] as String,
        value: j['value'] as String,
        action: j['action'] as String,
        actionValue: j['actionValue'] as String,
        priority: (j['priority'] as num?)?.toInt() ?? 0,
      );
}

class Budget {
  final String id;
  final String categoryId;
  final int monthlyCents;
  final int alertAtPercent;

  const Budget({required this.id, required this.categoryId, required this.monthlyCents, this.alertAtPercent = 80});

  Map<String, dynamic> toJson() => {'id': id, 'categoryId': categoryId, 'monthlyCents': monthlyCents, 'alertAtPercent': alertAtPercent};

  factory Budget.fromJson(Map<String, dynamic> j) => Budget(
        id: j['id'] as String,
        categoryId: j['categoryId'] as String,
        monthlyCents: (j['monthlyCents'] as num).toInt(),
        alertAtPercent: (j['alertAtPercent'] as num?)?.toInt() ?? 80,
      );
}

class Goal {
  final String id;
  final String name;
  final int targetCents;
  final DateTime? targetDate;
  final String? linkedAccountId;

  const Goal({required this.id, required this.name, required this.targetCents, this.targetDate, this.linkedAccountId});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'targetCents': targetCents,
        'targetDate': targetDate?.toIso8601String(),
        'linkedAccountId': linkedAccountId,
      };

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
        id: j['id'] as String,
        name: j['name'] as String,
        targetCents: (j['targetCents'] as num).toInt(),
        targetDate: j['targetDate'] != null ? DateTime.parse(j['targetDate'] as String) : null,
        linkedAccountId: j['linkedAccountId'] as String?,
      );
}

class Insight {
  final String id;
  final InsightType type;
  final String title;
  final String detail;
  final int? potentialCentsPerYear;
  final DateTime createdAt;
  final DateTime? dismissedAt;
  final String? payloadJson;

  const Insight({
    required this.id,
    required this.type,
    required this.title,
    required this.detail,
    this.potentialCentsPerYear,
    required this.createdAt,
    this.dismissedAt,
    this.payloadJson,
  });

  bool get dismissed => dismissedAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'detail': detail,
        'potentialCentsPerYear': potentialCentsPerYear,
        'createdAt': createdAt.toIso8601String(),
        'dismissedAt': dismissedAt?.toIso8601String(),
        'payloadJson': payloadJson,
      };

  factory Insight.fromJson(Map<String, dynamic> j) => Insight(
        id: j['id'] as String,
        type: InsightType.values.firstWhere((t) => t.name == j['type'], orElse: () => InsightType.kategorieAuffaellig),
        title: j['title'] as String,
        detail: j['detail'] as String,
        potentialCentsPerYear: (j['potentialCentsPerYear'] as num?)?.toInt(),
        createdAt: DateTime.parse(j['createdAt'] as String),
        dismissedAt: j['dismissedAt'] != null ? DateTime.parse(j['dismissedAt'] as String) : null,
        payloadJson: j['payloadJson'] as String?,
      );
}

class NetworkLogEntry {
  final String id;
  final String host;
  final DateTime timestamp;
  final String purpose;

  const NetworkLogEntry({required this.id, required this.host, required this.timestamp, required this.purpose});

  Map<String, dynamic> toJson() => {'id': id, 'host': host, 'timestamp': timestamp.toIso8601String(), 'purpose': purpose};

  factory NetworkLogEntry.fromJson(Map<String, dynamic> j) => NetworkLogEntry(
        id: j['id'] as String,
        host: j['host'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
        purpose: j['purpose'] as String,
      );
}

class BankConnection {
  final String id;
  final String blz;
  final String fintsUrl;
  final String userId;
  final String bankName;
  final String tanMethod;
  final DateTime? lastScaDate;
  final DateTime? scaValidUntil;

  const BankConnection({
    required this.id,
    required this.blz,
    required this.fintsUrl,
    required this.userId,
    required this.bankName,
    this.tanMethod = '',
    this.lastScaDate,
    this.scaValidUntil,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'blz': blz,
        'fintsUrl': fintsUrl,
        'userId': userId,
        'bankName': bankName,
        'tanMethod': tanMethod,
        'lastScaDate': lastScaDate?.toIso8601String(),
        'scaValidUntil': scaValidUntil?.toIso8601String(),
      };

  factory BankConnection.fromJson(Map<String, dynamic> j) => BankConnection(
        id: j['id'] as String,
        blz: j['blz'] as String,
        fintsUrl: j['fintsUrl'] as String,
        userId: j['userId'] as String,
        bankName: j['bankName'] as String,
        tanMethod: j['tanMethod'] as String? ?? '',
        lastScaDate: j['lastScaDate'] != null ? DateTime.parse(j['lastScaDate'] as String) : null,
        scaValidUntil: j['scaValidUntil'] != null ? DateTime.parse(j['scaValidUntil'] as String) : null,
      );
}
