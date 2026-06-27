import 'package:claw_hub/domain/models/notification_event.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/domain/usecases/evaluate_notification.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造 [UserPreferences] 的便捷函数，默认通知全开、DND 关。
UserPreferences _prefs({
  bool notificationsEnabled = true,
  bool notifyOnReply = true,
  bool notifyOnError = true,
  bool notifyOnConnectionChange = true,
  bool dndEnabled = false,
  int dndStartHour = 22,
  int dndStartMinute = 0,
  int dndEndHour = 8,
  int dndEndMinute = 0,
}) {
  return UserPreferences(
    notificationsEnabled: notificationsEnabled,
    notifyOnReply: notifyOnReply,
    notifyOnError: notifyOnError,
    notifyOnConnectionChange: notifyOnConnectionChange,
    dndEnabled: dndEnabled,
    dndStartHour: dndStartHour,
    dndStartMinute: dndStartMinute,
    dndEndHour: dndEndHour,
    dndEndMinute: dndEndMinute,
  );
}

ReplyEvent _reply({String? serverId = 's1'}) => ReplyEvent(
  agentId: 'a',
  instanceId: 'i',
  agentName: '虾',
  contentPreview: '内容',
  messageServerId: serverId,
  messageClientId: 'c1',
);

void main() {
  group('EvaluateNotificationUseCase.evaluate', () {
    final usecase = EvaluateNotificationUseCase();

    test('master switch off -> drop', () {
      final decision = usecase.evaluate(
        _reply(),
        _prefs(notificationsEnabled: false),
        DateTime(2026, 6, 20, 12),
      );
      expect(decision, isA<DroppedDecision>());
    });

    test('reply switch off -> drop reply', () {
      final decision = usecase.evaluate(
        _reply(),
        _prefs(notifyOnReply: false),
        DateTime(2026, 6, 20, 12),
      );
      expect(decision, isA<DroppedDecision>());
    });

    test('reply switch on, no DND -> show with truncated summary', () {
      final decision = usecase.evaluate(
        ReplyEvent(
          agentId: 'a',
          instanceId: 'i',
          agentName: '虾',
          contentPreview: '一' * 80,
          messageServerId: 's1',
          messageClientId: 'c1',
        ),
        _prefs(),
        DateTime(2026, 6, 20, 12),
      );
      expect(decision, isA<ShowDecision>());
      final show = decision as ShowDecision;
      expect(show.title, contains('虾'));
      // summary capped at 50 chars
      expect(show.body.length, lessThanOrEqualTo(50));
      expect(show.body, '一' * 50);
    });

    test('DND active (cross-midnight 22-08, now 03:00) -> suppress', () {
      final decision = usecase.evaluate(
        _reply(),
        _prefs(dndEnabled: true),
        DateTime(2026, 6, 20, 3, 0),
      );
      expect(decision, isA<DndSuppressedDecision>());
    });

    test('DND active (cross-midnight 22-08, now 23:00) -> suppress', () {
      final decision = usecase.evaluate(
        _reply(),
        _prefs(dndEnabled: true),
        DateTime(2026, 6, 20, 23, 0),
      );
      expect(decision, isA<DndSuppressedDecision>());
    });

    test('DND disabled -> show even at 03:00', () {
      final decision = usecase.evaluate(
        _reply(),
        _prefs(dndEnabled: false),
        DateTime(2026, 6, 20, 3, 0),
      );
      expect(decision, isA<ShowDecision>());
    });

    test('DND window 22-08, now 15:00 (outside) -> show', () {
      final decision = usecase.evaluate(
        _reply(),
        _prefs(dndEnabled: true),
        DateTime(2026, 6, 20, 15, 0),
      );
      expect(decision, isA<ShowDecision>());
    });

    test('DND window 22-08, now exactly 22:00 (start) -> suppress', () {
      final decision = usecase.evaluate(
        _reply(),
        _prefs(dndEnabled: true),
        DateTime(2026, 6, 20, 22, 0),
      );
      expect(decision, isA<DndSuppressedDecision>());
    });

    test('DND window 22-08, now exactly 08:00 (end) -> show', () {
      final decision = usecase.evaluate(
        _reply(),
        _prefs(dndEnabled: true),
        DateTime(2026, 6, 20, 8, 0),
      );
      expect(decision, isA<ShowDecision>());
    });

    test('non-cross-midnight DND 13-14, now 13:30 -> suppress', () {
      final decision = usecase.evaluate(
        _reply(),
        _prefs(dndEnabled: true, dndStartHour: 13, dndEndHour: 14),
        DateTime(2026, 6, 20, 13, 30),
      );
      expect(decision, isA<DndSuppressedDecision>());
    });

    test('connection change: online drop, switch on -> show', () {
      final decision = usecase.evaluate(
        ConnectionChangeEvent(
          instanceId: 'i',
          instanceName: '家里',
          fromState: NotificationConnectionState.online,
          toState: NotificationConnectionState.offline,
        ),
        _prefs(),
        DateTime(2026, 6, 20, 12),
      );
      expect(decision, isA<ShowDecision>());
    });

    test(
      'connection change: reconnecting->online, switch on -> drop (noise)',
      () {
        final decision = usecase.evaluate(
          ConnectionChangeEvent(
            instanceId: 'i',
            instanceName: '家里',
            fromState: NotificationConnectionState.reconnecting,
            toState: NotificationConnectionState.online,
          ),
          _prefs(),
          DateTime(2026, 6, 20, 12),
        );
        // reconnect success is not a "drop" — treated as noise by default to
        // avoid spamming during flaky networks.
        expect(decision, isA<DroppedDecision>());
      },
    );

    test(
      'connection change: online -> reconnecting, switch on -> drop (noise)',
      () {
        final decision = usecase.evaluate(
          ConnectionChangeEvent(
            instanceId: 'i',
            instanceName: '家里',
            fromState: NotificationConnectionState.online,
            toState: NotificationConnectionState.reconnecting,
          ),
          _prefs(),
          DateTime(2026, 6, 20, 12),
        );
        // reconnecting 是自动重连的中间状态，不应视为掉线通知。
        expect(decision, isA<DroppedDecision>());
      },
    );

    test('connection change switch off -> drop', () {
      final decision = usecase.evaluate(
        ConnectionChangeEvent(
          instanceId: 'i',
          instanceName: '家里',
          fromState: NotificationConnectionState.online,
          toState: NotificationConnectionState.offline,
        ),
        _prefs(notifyOnConnectionChange: false),
        DateTime(2026, 6, 20, 12),
      );
      expect(decision, isA<DroppedDecision>());
    });

    test('error event, switch on -> show', () {
      final decision = usecase.evaluate(
        ErrorEvent(
          agentId: 'a',
          instanceId: 'i',
          agentName: '虾',
          errorSummary: 'boom',
        ),
        _prefs(),
        DateTime(2026, 6, 20, 12),
      );
      expect(decision, isA<ShowDecision>());
    });

    test('error event, switch off -> drop', () {
      final decision = usecase.evaluate(
        ErrorEvent(
          agentId: 'a',
          instanceId: 'i',
          agentName: '虾',
          errorSummary: 'boom',
        ),
        _prefs(notifyOnError: false),
        DateTime(2026, 6, 20, 12),
      );
      expect(decision, isA<DroppedDecision>());
    });
  });

  group('EvaluateNotificationUseCase.isInDnd', () {
    final usecase = EvaluateNotificationUseCase();

    test('DND disabled -> never in DND', () {
      expect(
        usecase.isInDnd(_prefs(dndEnabled: false), DateTime(2026, 6, 20, 3)),
        isFalse,
      );
    });

    test('cross-midnight 22-08 boundaries', () {
      final p = _prefs(dndEnabled: true);
      expect(usecase.isInDnd(p, DateTime(2026, 6, 20, 23, 30)), isTrue);
      expect(usecase.isInDnd(p, DateTime(2026, 6, 20, 3, 0)), isTrue);
      expect(
        usecase.isInDnd(p, DateTime(2026, 6, 20, 22, 0)),
        isTrue,
      ); // start inclusive
      expect(
        usecase.isInDnd(p, DateTime(2026, 6, 20, 8, 0)),
        isFalse,
      ); // end exclusive
      expect(usecase.isInDnd(p, DateTime(2026, 6, 20, 15, 0)), isFalse);
    });
  });

  group('EvaluateNotificationUseCase.nextDndEndTime', () {
    final usecase = EvaluateNotificationUseCase();

    test('DND disabled -> null', () {
      expect(
        usecase.nextDndEndTime(
          _prefs(dndEnabled: false),
          DateTime(2026, 6, 20, 3),
        ),
        isNull,
      );
    });

    test('outside DND window -> null', () {
      expect(
        usecase.nextDndEndTime(
          _prefs(dndEnabled: true),
          DateTime(2026, 6, 20, 15),
        ),
        isNull,
      );
    });

    test('inside cross-midnight DND at 03:00 -> ends today 08:00', () {
      final end = usecase.nextDndEndTime(
        _prefs(dndEnabled: true),
        DateTime(2026, 6, 20, 3, 0),
      );
      expect(end, DateTime(2026, 6, 20, 8, 0));
    });

    test('inside cross-midnight DND at 23:00 -> ends next day 08:00', () {
      final end = usecase.nextDndEndTime(
        _prefs(dndEnabled: true),
        DateTime(2026, 6, 20, 23, 0),
      );
      expect(end, DateTime(2026, 6, 21, 8, 0));
    });

    test(
      'inside non-cross-midnight DND 13-14 at 13:30 -> ends today 14:00',
      () {
        final end = usecase.nextDndEndTime(
          _prefs(dndEnabled: true, dndStartHour: 13, dndEndHour: 14),
          DateTime(2026, 6, 20, 13, 30),
        );
        expect(end, DateTime(2026, 6, 20, 14, 0));
      },
    );

    test('all-day DND (start==end) -> isInDnd true, no end time (null)', () {
      // start==end 视为全天静默：永远在 DND 内，但没有"结束时刻"，
      // 因此 nextDndEndTime 返回 null（coordinator 不排 Timer、不周期性补发）。
      // 积压条目改由用户关闭 DND 时由 coordinator 的 onPrefsChanged 触发补发。
      final p = _prefs(dndEnabled: true, dndStartHour: 0, dndEndHour: 0);
      expect(usecase.isInDnd(p, DateTime(2026, 6, 20, 12, 0)), isTrue);
      expect(usecase.nextDndEndTime(p, DateTime(2026, 6, 20, 12, 0)), isNull);
    });
  });

  group('EvaluateNotificationUseCase.nextDndStartTime', () {
    final usecase = EvaluateNotificationUseCase();

    test('DND disabled -> null', () {
      expect(
        usecase.nextDndStartTime(
          _prefs(dndEnabled: false),
          DateTime(2026, 6, 20, 15),
        ),
        isNull,
      );
    });

    test('already inside DND -> null (no future start while active)', () {
      expect(
        usecase.nextDndStartTime(
          _prefs(dndEnabled: true),
          DateTime(2026, 6, 20, 3, 0),
        ),
        isNull,
      );
    });

    test('outside cross-midnight DND at 15:00 -> starts today 22:00', () {
      final start = usecase.nextDndStartTime(
        _prefs(dndEnabled: true),
        DateTime(2026, 6, 20, 15, 0),
      );
      expect(start, DateTime(2026, 6, 20, 22, 0));
    });

    test('outside cross-midnight DND at 09:00 -> starts today 22:00', () {
      // 09:00 is after the 08:00 end and before the 22:00 start (same day).
      final start = usecase.nextDndStartTime(
        _prefs(dndEnabled: true),
        DateTime(2026, 6, 20, 9, 0),
      );
      expect(start, DateTime(2026, 6, 20, 22, 0));
    });

    test(
      'outside non-cross-midnight DND 13-14 at 15:00 -> starts next day 13:00',
      () {
        final start = usecase.nextDndStartTime(
          _prefs(dndEnabled: true, dndStartHour: 13, dndEndHour: 14),
          DateTime(2026, 6, 20, 15, 0),
        );
        expect(start, DateTime(2026, 6, 21, 13, 0));
      },
    );

    test('all-day DND (start==end) -> null (no discrete start)', () {
      expect(
        usecase.nextDndStartTime(
          _prefs(dndEnabled: true, dndStartHour: 0, dndEndHour: 0),
          DateTime(2026, 6, 20, 12, 0),
        ),
        isNull,
      );
    });
  });

  group('summary truncation', () {
    final usecase = EvaluateNotificationUseCase();

    test('short summary unchanged', () {
      final d =
          usecase.evaluate(
                ReplyEvent(
                  agentId: 'a',
                  instanceId: 'i',
                  agentName: '虾',
                  contentPreview: '短消息',
                  messageServerId: 's',
                  messageClientId: 'c',
                ),
                _prefs(),
                DateTime(2026, 6, 20, 12),
              )
              as ShowDecision;
      expect(d.body, '短消息');
    });

    test('whitespace collapsed before truncation', () {
      final d =
          usecase.evaluate(
                ReplyEvent(
                  agentId: 'a',
                  instanceId: 'i',
                  agentName: '虾',
                  contentPreview: '  多\n  空格  ',
                  messageServerId: 's',
                  messageClientId: 'c',
                ),
                _prefs(),
                DateTime(2026, 6, 20, 12),
              )
              as ShowDecision;
      expect(d.body, '多 空格');
    });
  });
}
