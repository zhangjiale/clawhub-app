import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/lifecycle/background_sync_gate.dart';
import 'package:claw_hub/core/lifecycle/i_background_sync_prefs.dart';

class _FakePrefs implements IBackgroundSyncPrefs {
  bool value = false;
  Map<String, int> writes = {};
  @override
  Future<bool> get mainActive => Future.value(value);
  @override
  Future<void> setMainActive(bool active) async {
    value = active;
    writes['mainActive'] = active ? 1 : 0;
  }

  @override
  Future<void> clear() async {
    value = false;
  }
}

void main() {
  late _FakePrefs prefs;
  late BackgroundSyncGate gate;

  setUp(() {
    prefs = _FakePrefs();
    gate = BackgroundSyncGate(prefs: prefs);
  });

  test('shouldSkip_returnsTrueWhenMainActive', () async {
    prefs.value = true;
    expect(await gate.shouldSkip(), isTrue);
  });

  test('shouldSkip_returnsFalseWhenMainInactive', () async {
    prefs.value = false;
    expect(await gate.shouldSkip(), isFalse);
  });

  test('setMainActive_persistsAcrossReads', () async {
    await gate.setMainActive(true);
    expect(await gate.shouldSkip(), isTrue); // same process re-read
    await gate.setMainActive(false);
    expect(await gate.shouldSkip(), isFalse);
  });

  test('setMainActive_writesAndReadsAtomically', () async {
    await gate.setMainActive(true);
    expect(prefs.writes['mainActive'], 1);
    expect(prefs.value, isTrue);
    await gate.setMainActive(false);
    expect(prefs.writes['mainActive'], 0);
    expect(prefs.value, isFalse);
  });

  test('clear_resetsToInactive', () async {
    await gate.setMainActive(true);
    await gate.clear();
    expect(await gate.shouldSkip(), isFalse);
  });
}
