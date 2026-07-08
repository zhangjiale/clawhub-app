import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/core/api_log_redactor.dart';

void main() {
  group('redactAndTruncate', () {
    test('redacts top-level token', () {
      final raw =
          '{"method":"connect","params":{"auth":{"token":"secret-abc"}}}';
      final out = redactAndTruncate(raw);
      expect(out, contains('"token":"<redacted>"'));
      expect(out, isNot(contains('secret-abc')));
    });

    test('redacts nested auth.token (structured path)', () {
      final raw =
          '{"params":{"auth":{"token":"t1"}},"device":{"signature":"sig","nonce":"n1","publicKey":"pk"}}';
      final out = redactAndTruncate(raw);
      expect(out, contains('"token":"<redacted>"'));
      expect(out, contains('"signature":"<redacted>"'));
      expect(out, contains('"nonce":"<redacted>"'));
      expect(out, contains('"publicKey":"pk"')); // publicKey NOT redacted
      expect(out, isNot(contains('t1')));
      expect(out, isNot(contains('"sig"')));
    });

    test('redacts authToken / sessionToken / bearerToken', () {
      final raw = '{"authToken":"a","sessionToken":"b","bearerToken":"c"}';
      final out = redactAndTruncate(raw);
      expect(out, isNot(contains('"a"')));
      expect(out, isNot(contains('"b"')));
      expect(out, isNot(contains('"c"')));
      expect(out, contains('<redacted>'));
    });

    test('preserves payload ≤ maxBytes intact', () {
      final raw = '{"method":"agents.list","params":{}}';
      final out = redactAndTruncate(raw, maxBytes: 2048);
      expect(out, raw);
    });

    test('truncates > maxBytes with marker including original byte count', () {
      final big = '{"x":"${'a' * 5000}"}';
      final out = redactAndTruncate(big, maxBytes: 100);
      expect(out, contains('…(truncated,'));
      expect(out, contains('bytes total)'));
      // original byte count ~5000+ overhead
      expect(out.length, lessThan(200));
    });

    test(
      'large frame (payloadSize > 64KB) skips jsonDecode — does not parse full body',
      () {
        // A 70KB frame whose tail is malformed JSON; if jsonDecode ran on the whole
        // thing it would throw and fall to regex anyway. The point: large-frame path
        // only scans the first 8KB.
        final head =
            '{"method":"chat.send","params":{"message":"hi","auth":{"token":"t-big"}}}';
        final padding = ' ' * 70000;
        final raw = '$head$padding}'; // overall > 64KB
        final out = redactAndTruncate(raw, payloadSize: 70050);
        expect(out, contains('"token":"<redacted>"')); // head scanned by regex
        expect(out, contains('truncated'));
      },
    );

    test(
      'malformed JSON with nested auth.token → regex fallback still redacts',
      () {
        // Broken JSON (unterminated) that jsonDecode rejects; regex must still catch token.
        final raw = '{"params":{"auth":{"token":"leak-me"';
        final out = redactAndTruncate(raw);
        expect(out, contains('"token":"<redacted>"'));
        expect(out, isNot(contains('leak-me')));
      },
    );

    test('never throws on garbage input', () {
      expect(() => redactAndTruncate(''), returnsNormally);
      expect(() => redactAndTruncate('not json at all {{{'), returnsNormally);
    });

    test(
      'regex fallback redacts a secret containing an escaped quote (ARB #6)',
      () {
        // Malformed JSON (unterminated) -> jsonDecode throws -> regex fallback
        // path (_regexRedact). The token value contains an escaped quote
        // (`\"`). The naive regex `"[^"]*"` stops at the first quote, so it
        // matches only `"abc\"` and leaves the `def"` tail in the preview -
        // leaking the secret suffix AND corrupting the JSON shown on the
        // diagnostics page. The fix uses a JSON-string-aware regex that honors
        // backslash escapes so the whole value is redacted.
        const raw = '{"token":"abc\\"def","x":"y';
        final out = redactAndTruncate(raw);
        expect(out, contains('"token":"<redacted>"'));
        expect(
          out,
          isNot(contains('abc')),
          reason: 'value prefix must not leak',
        );
        expect(
          out,
          isNot(contains('def')),
          reason: 'value suffix must not leak',
        );
      },
    );
  });
}
