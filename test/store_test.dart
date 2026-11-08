import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klarblick/core/engine/normalize.dart';
import 'package:klarblick/data/blob/blob_storage.dart';
import 'package:klarblick/data/models.dart';
import 'package:klarblick/data/secure_key.dart';
import 'package:klarblick/data/store.dart';

import 'helpers.dart';

Transaction _t(String id, int cents, {bool manual = false, String? cat}) => Transaction(
      id: id,
      accountId: 'a',
      bookingDate: DateTime(2026, 10, 1),
      amountCents: cents,
      counterpartyName: 'X$id',
      categoryId: cat,
      manualCategory: manual,
      dedupHash: dedupHash('a', DateTime(2026, 10, 1), cents, id, 'X$id'),
    );

void main() {
  test('verschlüsselt speichern und wieder laden', () async {
    final blob = MemoryBlobStorage();
    final keys = MemorySecureKeyStore();
    final s1 = memoryStore(blob: blob, keys: keys);
    await s1.load();
    s1.upsertAccount(const Account(id: 'a', iban: 'DE00', name: 'Giro', type: AccountType.giro, balanceCents: 12345));
    s1.upsertTransactions([_t('1', -500), _t('2', 1000)]);
    await s1.save();
    expect(blob.data, startsWith('KB2:'));
    expect(blob.data, isNot(contains('Giro')));

    final s2 = memoryStore(blob: blob, keys: keys);
    await s2.load();
    expect(s2.loadError, isNull);
    expect(s2.accounts.single.balanceCents, 12345);
    expect(s2.transactions, hasLength(2));
    s1.dispose();
    s2.dispose();
  });

  test('jeder Speichervorgang nutzt einen neuen Nonce', () async {
    final blob = MemoryBlobStorage();
    final s = memoryStore(blob: blob);
    await s.load();
    await s.save();
    final a = blob.data;
    await s.save();
    expect(blob.data, isNot(a));
    s.dispose();
  });

  test('Legacy-Container (fester IV) wird gelesen', () async {
    final keys = MemorySecureKeyStore();
    final raw = await keys.getOrCreateDatabaseKey();
    final derived = deriveDatabaseKey(raw);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonEncode({
        'accounts': [const Account(id: 'old', iban: '', name: 'Alt', type: AccountType.giro).toJson()],
      })),
      secretKey: SecretKey(derived),
      nonce: derived.sublist(0, 12),
    );
    final blob = MemoryBlobStorage()..data = base64Encode([...box.cipherText, ...box.mac.bytes]);
    final s = memoryStore(blob: blob, keys: keys);
    await s.load();
    expect(s.accounts.single.name, 'Alt');
    s.dispose();
  });

  test('beschädigter Container wird gesichert statt überschrieben', () async {
    final blob = MemoryBlobStorage()..data = 'KB2:kaputt';
    final s = memoryStore(blob: blob);
    await s.load();
    expect(s.loadError, isNotNull);
    expect(blob.corrupt, 'KB2:kaputt');
    s.dispose();
  });

  test('Dedup behält Nutzerangaben', () async {
    final s = memoryStore();
    await s.load();
    expect(s.upsertTransactions([_t('1', -500)]), 1);
    s.upsertTransaction(s.transactions.single.copyWith(categoryId: 'hobby', manualCategory: true, note: 'Geschenk'));
    expect(s.upsertTransactions([_t('1', -500)]), 0);
    expect(s.transactions.single.categoryId, 'hobby');
    expect(s.transactions.single.note, 'Geschenk');
    s.dispose();
  });

  test('ausgeblendete Spar-Hinweise bleiben ausgeblendet', () async {
    final s = memoryStore();
    await s.load();
    final i = Insight(id: 'ins_x', type: InsightType.bankgebuehren, title: 'T', detail: 'D', createdAt: DateTime(2026));
    s.replaceInsights([i]);
    s.dismissInsight('ins_x');
    s.replaceInsights([i]);
    expect(s.insights.single.dismissed, isTrue);
    s.replaceInsights([]);
    expect(s.insights.single.dismissed, isTrue, reason: 'Ausblendung bleibt gemerkt');
    s.dispose();
  });

  test('wipe löscht alles inkl. PINs', () async {
    final keys = MemorySecureKeyStore();
    final blob = MemoryBlobStorage();
    final s = memoryStore(blob: blob, keys: keys);
    await s.load();
    s.upsertConnection(const BankConnection(id: 'c', blz: '12030000', fintsUrl: 'https://x', userId: 'u', bankName: 'B'));
    await keys.write(Store.pinKeyFor('c'), '1234');
    await s.save();
    await s.wipe();
    expect(s.connections, isEmpty);
    expect(await keys.read(Store.pinKeyFor('c')), isNull);
    expect(blob.data, isNull);
    s.dispose();
  });
}
