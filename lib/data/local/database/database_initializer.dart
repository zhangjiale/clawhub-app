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

        // Create FTS5 virtual table if it doesn't exist yet.
        // Drift's code generator does not process CREATE VIRTUAL TABLE
        // statements from schema.drift, so we create it here.
        // Safe in setup: does not reference any drift-managed tables.
        db.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
            content,
            content='messages',
            content_rowid='rowid'
          )
        ''');

        // Backfill FTS5 index for messages that were persisted before the
        // FTS5 virtual table existed (e.g. first launch after upgrade).
        //
        // The guard (SELECT COUNT(*) FROM messages_fts) = 0 avoids a full
        // messages table scan on every subsequent database open: once the
        // initial backfill completes, per-insert FTS sync in
        // DriftMessageRepo keeps the index current, so the backfill query
        // can be skipped entirely.
        //
        // NOT EXISTS short-circuits on the first matching row in
        // messages_fts, which is cheaper than NOT IN for large datasets.
        db.execute('''
          INSERT INTO messages_fts(rowid, content)
          SELECT m.rowid, m.content FROM messages m
          WHERE (SELECT COUNT(*) FROM messages_fts) = 0
            AND NOT EXISTS (
              SELECT 1 FROM messages_fts f WHERE f.rowid = m.rowid
            )
        ''');
      },
    ),
  );
}
