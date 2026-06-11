import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// ignore: unused_import
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart'; // Required: registers Flutter SQLite for drift

import 'database.dart';

/// Creates and configures the AppDatabase instance.
///
/// Must be called before [runApp] to ensure the database is
/// ready before any Riverpod providers attempt to use it.
///
/// The [sqlite3_flutter_libs] package is imported transitively and
/// automatically replaces the system SQLite on both Android and iOS,
/// providing consistent behavior and FTS5 support.
Future<AppDatabase> createAppDatabase() async {
  final dbDir = await getApplicationDocumentsDirectory();
  final dbPath = p.join(dbDir.path, 'clawhub.db');

  return AppDatabase(
    NativeDatabase(
      File(dbPath),
      setup: (db) {
        db.execute('PRAGMA foreign_keys = ON');
        db.execute('PRAGMA journal_mode = WAL');
      },
    ),
  );
}
