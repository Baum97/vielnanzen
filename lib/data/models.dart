/// Kern-Datenmodell von Klarblick.
/// Alle Beträge werden als Ganzzahl in Cent gespeichert (nie Gleitkomma).
library;

enum AccountType { giro, kreditkarte, tagesgeld, depot, bargeld, manual }

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
  aboKosten,
  kleinvieh,
  lieferdienst,
  versicherungCheck,
  energieCheck,
  ungenutztesAbo,
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

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
        icon: j['icon'] as String? ?? 'other',
        color: j['color'] as String? ?? '#9A9EA5',
        kind: CategoryKind.values.firstWhere(
          (k) => k.name == (j['kind'] as String? ?? '').toLowerCase(),
          orElse: () => CategoryKind.ausgabe,
        ),
      );
}

class Merchant {
  final String id;
  final String displayName;
  final List<String> patterns;
  final String? defaultCategoryId;
  final bool subscription;
  final bool aggregator;

  /// Gruppe gleichartiger Dienste (z. B. "video", "music", "gym") – erkennt Doppel-Abos.
  final String? group;

  const Merchant({
    required this.id,
    required this.displayName,
    this.patterns = const [],
    this.defaultCategoryId,
    this.subscription = false,
    this.aggregator = false,
    this.group,
  });

  factory Merchant.fromJson(Map<String, dynamic> j) => Merchant(
        id: j['id'] as String,
        displayName: j['displayName'] as String,
        patterns: (j['patterns'] as List? ?? const []).map((e) => (e as String).toUpperCase()).toList(),
        defaultCategoryId: j['category'] as String?,
        subscription: j['subscription'] as bool? ?? false,
        aggregator: j['aggregator'] as bool? ?? false,
        group: j['group'] as String?,
      );
}

class Account {
  final String id;
  final String? connectionId;
  final String iban;
  final String? accountNumber;
  final String? bankCode;
  final String name;
  final AccountType type;
  final String currency;
  final int balanceCents;
  final DateTime? balanceDate;
  final DateTime? lastSync;
  final String color;
  final bool hidden;
  final bool includeInTotal;

  const Account({
    required this.id,
    this.connectionId,
    required this.iban,
    this.accountNumber,
    this.bankCode,
    required this.name,
    required this.type,
    this.currency = 'EUR',
    this.balanceCents = 0,
    this.balanceDate,
    this.lastSync,
    this.color = '#2F5BEA',
    this.hidden = false,
    this.includeInTotal = true,
  });

  bool get isManual => connectionId == null;

  Account copyWith({
    String? name,
    int? balanceCents,
    DateTime? balanceDate,
    DateTime? lastSync,
    String? color,
    bool? hidden,
    bool? includeInTotal,
    AccountType? type,
  }) =>
      Account(
        id: id,
        connectionId: connectionId,
        iban: iban,
        accountNumber: accountNumber,
        bankCode: bankCode,
        name: name ?? this.name,
        type: type ?? this.type,
        currency: currency,
        balanceCents: balanceCents ?? this.balanceCents,
        balanceDate: balanceDate ?? this.balanceDate,
        lastSync: lastSync ?? this.lastSync,
        color: color ?? this.color,
        hidden: hidden ?? this.hidden,
        includeInTotal: includeInTotal ?? this.includeInTotal,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'connectionId': connectionId,
        'iban': iban,
        'accountNumber': accountNumber,
        'bankCode': bankCode,
        'name': name,
        'type': type.name,
        'currency': currency,
        'balanceCents': balanceCents,
        'balanceDate': balanceDate?.toIso8601String(),
        'lastSync': lastSync?.toIso8601String(),
        'color': color,
        'hidden': hidden,
        'includeInTotal': includeInTotal,
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        connectionId: j['connectionId'] as String?,
        iban: j['iban'] as String? ?? '',
        accountNumber: j['accountNumber'] as String?,
        bankCode: j['bankCode'] as String?,
        name: j['name'] as String? ?? 'Konto',
        type: AccountType.values.firstWhere((t) => t.name == j['type'], orElse: () => AccountType.manual),
        currency: j['currency'] as String? ?? 'EUR',
        balanceCents: (j['balanceCents'] as num? ?? 0).toInt(),
        balanceDate: _date(j['balanceDate']),
        lastSync: _date(j['lastSync']),
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

  /// Vom Nutzer gesetzte Kategorie – wird von der Analyse nie überschrieben.
  final bool manualCategory;

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
    this.manualCategory = false,
  });

  bool get isIncome => amountCents > 0;
  bool get isExpense => amountCents < 0;

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
        'manualCategory': manualCategory,
      };

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: j['id'] as String,
        accountId: j['accountId'] as String,
        bookingDate: DateTime.parse(j['bookingDate'] as String),
        valueDate: _date(j['valueDate']),
        amountCents: (j['amountCents'] as num).toInt(),
        counterpartyName: j['counterpartyName'] as String? ?? '',
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
        manualCategory: j['manualCategory'] as bool? ?? false,
      );

  /// Für nullable Felder gilt: ein explizites `null` wird über die `clear*`-Flags gesetzt.
  Transaction copyWith({
    String? categoryId,
    String? merchantId,
    String? contractId,
    bool clearContract = false,
    bool clearMerchant = false,
    bool? isTransfer,
    bool? excluded,
    bool? pending,
    String? note,
    List<String>? tags,
    String? categoryReason,
    bool? manualCategory,
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
        merchantId: clearMerchant ? null : (merchantId ?? this.merchantId),
        contractId: clearContract ? null : (contractId ?? this.contractId),
        isTransfer: isTransfer ?? this.isTransfer,
        excluded: excluded ?? this.excluded,
        note: note ?? this.note,
        tags: tags ?? this.tags,
        categoryReason: categoryReason ?? this.categoryReason,
        manualCategory: manualCategory ?? this.manualCategory,
      );
}

class Contract {
  final String id;
  final String? merchantId;
  final String name;
  final ContractInterval interval;
  final int expectedCents;
  final DateTime? nextDue;
  final DateTime? lastPayment;
  final int? previousCents;
  final double confidence;
  final ContractStatus status;
  final String? noticePeriod;
  final DateTime? minTermEnd;
  final String? reminder;
  final String? categoryId;
  final String? accountId;
  final String? reason;
  final List<String> transactionIds;

  /// true = vom Nutzer angelegt/bestätigt; die Analyse ändert dann nur Zahlungsdaten.
  final bool userConfirmed;

  const Contract({
    required this.id,
    this.merchantId,
    required this.name,
    required this.interval,
    required this.expectedCents,
    this.nextDue,
    this.lastPayment,
    this.previousCents,
    this.confidence = 0,
    this.status = ContractStatus.vorschlag,
    this.noticePeriod,
    this.minTermEnd,
    this.reminder,
    this.categoryId,
    this.accountId,
    this.reason,
    this.transactionIds = const [],
    this.userConfirmed = false,
  });

  bool get isRunning => status == ContractStatus.aktiv || status == ContractStatus.vorschlag;

  static int daysOf(ContractInterval i) => switch (i) {
        ContractInterval.woechentlich => 7,
        ContractInterval.zweiwoechentlich => 14,
        ContractInterval.monatlich => 30,
        ContractInterval.quartalsweise => 91,
        ContractInterval.halbjahrlich => 182,
        ContractInterval.jaehrlich => 365,
        ContractInterval.individuell => 30,
      };

  double get monthlyCents => switch (interval) {
        ContractInterval.woechentlich => expectedCents * 52 / 12,
        ContractInterval.zweiwoechentlich => expectedCents * 26 / 12,
        ContractInterval.monatlich => expectedCents.toDouble(),
        ContractInterval.quartalsweise => expectedCents / 3,
        ContractInterval.halbjahrlich => expectedCents / 6,
        ContractInterval.jaehrlich => expectedCents / 12,
        ContractInterval.individuell => expectedCents.toDouble(),
      };

  int get yearlyCents => (monthlyCents * 12).round();

  Contract copyWith({
    String? name,
    ContractInterval? interval,
    int? expectedCents,
    DateTime? nextDue,
    DateTime? lastPayment,
    int? previousCents,
    double? confidence,
    ContractStatus? status,
    String? categoryId,
    String? merchantId,
    String? accountId,
    String? reason,
    List<String>? transactionIds,
    bool? userConfirmed,
    String? noticePeriod,
  }) =>
      Contract(
        id: id,
        merchantId: merchantId ?? this.merchantId,
        name: name ?? this.name,
        interval: interval ?? this.interval,
        expectedCents: expectedCents ?? this.expectedCents,
        nextDue: nextDue ?? this.nextDue,
        lastPayment: lastPayment ?? this.lastPayment,
        previousCents: previousCents ?? this.previousCents,
        confidence: confidence ?? this.confidence,
        status: status ?? this.status,
        noticePeriod: noticePeriod ?? this.noticePeriod,
        minTermEnd: minTermEnd,
        reminder: reminder,
        categoryId: categoryId ?? this.categoryId,
        accountId: accountId ?? this.accountId,
        reason: reason ?? this.reason,
        transactionIds: transactionIds ?? this.transactionIds,
        userConfirmed: userConfirmed ?? this.userConfirmed,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'merchantId': merchantId,
        'name': name,
        'interval': interval.name,
        'expectedCents': expectedCents,
        'nextDue': nextDue?.toIso8601String(),
        'lastPayment': lastPayment?.toIso8601String(),
        'previousCents': previousCents,
        'confidence': confidence,
        'status': status.name,
        'noticePeriod': noticePeriod,
        'minTermEnd': minTermEnd?.toIso8601String(),
        'reminder': reminder,
        'categoryId': categoryId,
        'accountId': accountId,
        'reason': reason,
        'transactionIds': transactionIds,
        'userConfirmed': userConfirmed,
      };

  factory Contract.fromJson(Map<String, dynamic> j) => Contract(
        id: j['id'] as String,
        merchantId: j['merchantId'] as String?,
        name: j['name'] as String? ?? 'Vertrag',
        interval: ContractInterval.values.firstWhere((i) => i.name == j['interval'], orElse: () => ContractInterval.monatlich),
        expectedCents: (j['expectedCents'] as num? ?? 0).toInt(),
        nextDue: _date(j['nextDue']),
        lastPayment: _date(j['lastPayment']),
        previousCents: (j['previousCents'] as num?)?.toInt(),
        confidence: (j['confidence'] as num? ?? 0).toDouble(),
        status: ContractStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => ContractStatus.vorschlag),
        noticePeriod: j['noticePeriod'] as String?,
        minTermEnd: _date(j['minTermEnd']),
        reminder: j['reminder'] as String?,
        categoryId: j['categoryId'] as String?,
        accountId: j['accountId'] as String?,
        reason: j['reason'] as String?,
        transactionIds: (j['transactionIds'] as List?)?.map((e) => e as String).toList() ?? const [],
        userConfirmed: j['userConfirmed'] as bool? ?? false,
      );
}

/// Eigene Kategorie-Regel: "Empfänger enthält X → Kategorie Y".
class Rule {
  final String id;
  final String field; // 'merchant' | 'counterparty' | 'purpose' | 'iban'
  final String operator; // 'contains' | 'equals'
  final String value;
  final String action; // 'category' | 'transfer' | 'exclude'
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
        targetDate: _date(j['targetDate']),
        linkedAccountId: j['linkedAccountId'] as String?,
      );
}

class Insight {
  /// Stabil pro Sachverhalt (kein Zeitstempel), damit Ausblenden dauerhaft wirkt.
  final String id;
  final InsightType type;
  final String title;
  final String detail;
  final String? action;
  final int? potentialCentsPerYear;
  final DateTime createdAt;
  final DateTime? dismissedAt;
  final String? contractId;
  final String? merchantName;
  final String? categoryId;

  const Insight({
    required this.id,
    required this.type,
    required this.title,
    required this.detail,
    this.action,
    this.potentialCentsPerYear,
    required this.createdAt,
    this.dismissedAt,
    this.contractId,
    this.merchantName,
    this.categoryId,
  });

  bool get dismissed => dismissedAt != null;

  Insight copyWith({DateTime? dismissedAt, DateTime? createdAt}) => Insight(
        id: id,
        type: type,
        title: title,
        detail: detail,
        action: action,
        potentialCentsPerYear: potentialCentsPerYear,
        createdAt: createdAt ?? this.createdAt,
        dismissedAt: dismissedAt ?? this.dismissedAt,
        contractId: contractId,
        merchantName: merchantName,
        categoryId: categoryId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'detail': detail,
        'action': action,
        'potentialCentsPerYear': potentialCentsPerYear,
        'createdAt': createdAt.toIso8601String(),
        'dismissedAt': dismissedAt?.toIso8601String(),
        'contractId': contractId,
        'merchantName': merchantName,
        'categoryId': categoryId,
      };

  factory Insight.fromJson(Map<String, dynamic> j) => Insight(
        id: j['id'] as String,
        type: InsightType.values.firstWhere((t) => t.name == j['type'], orElse: () => InsightType.kategorieAuffaellig),
        title: j['title'] as String,
        detail: j['detail'] as String,
        action: j['action'] as String?,
        potentialCentsPerYear: (j['potentialCentsPerYear'] as num?)?.toInt(),
        createdAt: _date(j['createdAt']) ?? DateTime.now(),
        dismissedAt: _date(j['dismissedAt']),
        contractId: j['contractId'] as String?,
        merchantName: j['merchantName'] as String?,
        categoryId: j['categoryId'] as String?,
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

/// Eine FinTS-Bankverbindung (ein Online-Banking-Zugang, ggf. mehrere Konten).
/// Die PIN liegt – wenn überhaupt – nur im sicheren Speicher (Keychain/Keystore), nie hier.
class BankConnection {
  final String id;
  final String blz;
  final String fintsUrl;
  final String userId;
  final String? customerId;
  final String bankName;
  final String tanMethod;
  final bool pinSaved;

  /// Sitzungsdaten des FinTS-Clients (BPD/UPD, Kundensystem-ID) – enthalten keine PIN.
  final String? fintsState;
  final DateTime? lastSync;
  final String? lastError;
  final DateTime? lastScaDate;
  final DateTime? scaValidUntil;

  const BankConnection({
    required this.id,
    required this.blz,
    required this.fintsUrl,
    required this.userId,
    this.customerId,
    required this.bankName,
    this.tanMethod = '',
    this.pinSaved = false,
    this.fintsState,
    this.lastSync,
    this.lastError,
    this.lastScaDate,
    this.scaValidUntil,
  });

  BankConnection copyWith({
    String? fintsState,
    DateTime? lastSync,
    String? lastError,
    bool clearError = false,
    bool? pinSaved,
    String? userId,
    String? customerId,
    DateTime? lastScaDate,
    DateTime? scaValidUntil,
  }) =>
      BankConnection(
        id: id,
        blz: blz,
        fintsUrl: fintsUrl,
        userId: userId ?? this.userId,
        customerId: customerId ?? this.customerId,
        bankName: bankName,
        tanMethod: tanMethod,
        pinSaved: pinSaved ?? this.pinSaved,
        fintsState: fintsState ?? this.fintsState,
        lastSync: lastSync ?? this.lastSync,
        lastError: clearError ? null : (lastError ?? this.lastError),
        lastScaDate: lastScaDate ?? this.lastScaDate,
        scaValidUntil: scaValidUntil ?? this.scaValidUntil,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'blz': blz,
        'fintsUrl': fintsUrl,
        'userId': userId,
        'customerId': customerId,
        'bankName': bankName,
        'tanMethod': tanMethod,
        'pinSaved': pinSaved,
        'fintsState': fintsState,
        'lastSync': lastSync?.toIso8601String(),
        'lastError': lastError,
        'lastScaDate': lastScaDate?.toIso8601String(),
        'scaValidUntil': scaValidUntil?.toIso8601String(),
      };

  factory BankConnection.fromJson(Map<String, dynamic> j) => BankConnection(
        id: j['id'] as String,
        blz: j['blz'] as String? ?? '',
        fintsUrl: j['fintsUrl'] as String? ?? '',
        userId: j['userId'] as String? ?? '',
        customerId: j['customerId'] as String?,
        bankName: j['bankName'] as String? ?? 'Bank',
        tanMethod: j['tanMethod'] as String? ?? '',
        pinSaved: j['pinSaved'] as bool? ?? false,
        fintsState: j['fintsState'] as String?,
        lastSync: _date(j['lastSync']),
        lastError: j['lastError'] as String?,
        lastScaDate: _date(j['lastScaDate']),
        scaValidUntil: _date(j['scaValidUntil']),
      );
}
