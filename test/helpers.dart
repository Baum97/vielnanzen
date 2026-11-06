import 'dart:io';

import 'package:klarblick/core/engine/engine.dart';
import 'package:klarblick/data/blob/blob_storage.dart';
import 'package:klarblick/data/secure_key.dart';
import 'package:klarblick/data/store.dart';

SeedData loadSeed() => SeedData.fromJsonStrings(
      categories: File('assets/data/categories.json').readAsStringSync(),
      merchants: File('assets/data/merchants.json').readAsStringSync(),
      creditors: File('assets/data/creditor_ids.json').readAsStringSync(),
    );

Store memoryStore({MemoryBlobStorage? blob, MemorySecureKeyStore? keys}) =>
    Store(keyStore: keys ?? MemorySecureKeyStore(), blob: blob ?? MemoryBlobStorage());
