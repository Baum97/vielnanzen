import 'package:fints/fints.dart' as fints;

import '../core/engine/normalize.dart';
import '../data/models.dart';

/// Übersetzt eine Buchung des fints-Pakets (FinTS, MT940, CAMT) in das App-Modell.
Transaction mapFintsTransaction(fints.Transaction t, String accountId) {
  final date = t.bookingDate ?? t.valueDate;
  final day = DateTime(date.year, date.month, date.day);
  final cents = _toCents(t.amount);
  final name = (t.counterpartyName?.trim().isNotEmpty ?? false)
      ? t.counterpartyName!.trim()
      : (t.ultimateCreditor ?? t.ultimateDebtor ?? t.bookingText ?? 'Unbekannt');
  final purpose = [t.purpose, if ((t.purpose ?? '').isEmpty) t.bookingText].whereType<String>().join(' ').trim();
  final e2e = (t.endToEndId == null || t.endToEndId!.toUpperCase() == 'NOTPROVIDED') ? null : t.endToEndId;
  final hash = dedupHash(accountId, day, cents, e2e, '$name $purpose');
  return Transaction(
    id: 'tx_${hash.substring(0, 20)}',
    accountId: accountId,
    bookingDate: day,
    valueDate: t.valueDate,
    amountCents: cents,
    counterpartyName: name,
    counterpartyIban: t.counterpartyIban,
    purpose: purpose,
    mandateRef: t.mandateId,
    creditorId: t.creditorId,
    endToEndRef: e2e,
    gvc: t.transactionCode,
    pending: t.isPending,
    dedupHash: hash,
  );
}

/// Betrag in Cent (Skalierung des Pakets kann von 2 abweichen).
int _toCents(fints.Amount a) {
  if (a.scale == 2) return a.minorUnits;
  if (a.scale < 2) {
    var v = a.minorUnits;
    for (var i = a.scale; i < 2; i++) {
      v *= 10;
    }
    return v;
  }
  var div = 1;
  for (var i = 2; i < a.scale; i++) {
    div *= 10;
  }
  return (a.minorUnits / div).round();
}

int amountToCents(fints.Amount a) => _toCents(a);
