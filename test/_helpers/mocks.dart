// Shared mocktail Mock* classes for tests that need to stub the same domain
// interfaces. Hoisted out of individual test files to avoid the 7-class
// declaration block that each agent_profile test used to repeat.
//
// Naming: public `Mock*` (no underscore) so any test file can import and
// reuse them. The shared file does NOT contain ILogger — tests that don't
// assert on log calls should use `FakeLogger` from `fake_logger.dart`
// (no-op ILogger), which is much cheaper than a mocktail mock.
//
// Why a separate file rather than `setUpAll`/mixin: each test wants
// independent mock instances (so verify() in one test doesn't bleed into
// another). Sharing the *class* definitions while constructing fresh
// instances per test gives the dedup benefit without the cross-test state
// contamination.

import 'package:claw_hub/core/i_avatar_storage_service.dart';
import 'package:claw_hub/core/i_logger.dart';
import 'package:claw_hub/domain/repositories/i_activity_repo.dart';
import 'package:claw_hub/domain/repositories/i_agent_repo.dart';
import 'package:claw_hub/domain/repositories/i_achievement_repo.dart';
import 'package:claw_hub/domain/repositories/i_instance_repo.dart';
import 'package:claw_hub/domain/repositories/i_message_repo.dart';
import 'package:claw_hub/domain/usecases/evaluate_achievements.dart';
import 'package:mocktail/mocktail.dart';

class MockAgentRepo extends Mock implements IAgentRepo {}

class MockInstanceRepo extends Mock implements IInstanceRepo {}

class MockMessageRepo extends Mock implements IMessageRepo {}

class MockAchievementRepo extends Mock implements IAchievementRepo {}

class MockActivityRepo extends Mock implements IActivityRepo {}

class MockAvatarStorageService extends Mock implements IAvatarStorageService {}

class MockEvaluateAchievementsUseCase extends Mock
    implements EvaluateAchievementsUseCase {}

/// mocktail mock for [ILogger] — use when the test asserts on log calls
/// (e.g. `verify(() => logger.error(...))`). For tests that only inject
/// a logger without verifying, use [FakeLogger] from `fake_logger.dart`
/// instead — cheaper and signals intent ("I don't care what was logged").
class MockILogger extends Mock implements ILogger {}
