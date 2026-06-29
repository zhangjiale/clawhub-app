import 'package:drift/native.dart';
import 'package:claw_hub/data/local/database/database.dart';
import 'package:claw_hub/data/repositories/drift_last_sync_repo.dart';

class RepoHarness {
  final AppDatabase db;
  final DriftLastSyncRepo repo;
  RepoHarness(this.db, this.repo);
}

Future<RepoHarness> openInMemory() async {
  final db = AppDatabase(NativeDatabase.memory());
  // beforeOpen runs on first query; force it:
  await db.customSelect('SELECT 1').get();
  return RepoHarness(db, DriftLastSyncRepo(db));
}

DriftLastSyncRepo makeRepo(AppDatabase db) => DriftLastSyncRepo(db);

extension on RepoHarness {
  Future<void> close() async => await db.close();
}
