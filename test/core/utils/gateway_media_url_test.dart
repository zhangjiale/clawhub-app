import 'package:claw_hub/core/utils/gateway_media_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('httpBaseFromWsUrl', () {
    test('ws://host:port/path → http://host:port', () {
      expect(
        httpBaseFromWsUrl('ws://192.168.1.5:3000/some/path'),
        'http://192.168.1.5:3000',
      );
    });

    test('wss://host:port → https://host:port', () {
      expect(
        httpBaseFromWsUrl('wss://example.com:443'),
        'https://example.com:443',
      );
    });

    test('ws://localhost:8080 → http://localhost:8080', () {
      expect(httpBaseFromWsUrl('ws://localhost:8080'), 'http://localhost:8080');
    });

    test('non-ws scheme returns null', () {
      expect(httpBaseFromWsUrl('http://example.com'), isNull);
      expect(httpBaseFromWsUrl('https://example.com'), isNull);
    });

    test('invalid URL returns null', () {
      expect(httpBaseFromWsUrl('not a url'), isNull);
      expect(httpBaseFromWsUrl(''), isNull);
    });

    test('strips trailing path/query from base', () {
      // Base must be scheme://host:port only — no path/query carried over.
      expect(
        httpBaseFromWsUrl('ws://10.0.0.2:9000/a/b?x=1'),
        'http://10.0.0.2:9000',
      );
    });
  });

  group('resolveGatewayMediaUrl', () {
    test('relative URL resolved against gatewayBaseUrl + flagged for auth', () {
      final r = resolveGatewayMediaUrl(
        '/api/chat/media/outgoing/abc/full',
        gatewayBaseUrl: 'http://192.168.1.5:3000',
      );
      expect(r.url, 'http://192.168.1.5:3000/api/chat/media/outgoing/abc/full');
      expect(r.needsAuth, isTrue);
    });

    test('absolute https URL returned unchanged, no auth', () {
      final r = resolveGatewayMediaUrl(
        'https://cdn.example.com/x.png',
        gatewayBaseUrl: 'http://192.168.1.5:3000',
      );
      expect(r.url, 'https://cdn.example.com/x.png');
      expect(r.needsAuth, isFalse);
    });

    test('absolute http URL returned unchanged, no auth', () {
      final r = resolveGatewayMediaUrl(
        'http://example.com/img.jpg',
        gatewayBaseUrl: 'http://192.168.1.5:3000',
      );
      expect(r.url, 'http://example.com/img.jpg');
      expect(r.needsAuth, isFalse);
    });

    test('data: URL returned unchanged, no auth', () {
      const dataUrl = 'data:image/png;base64,iVBORw0KGgo=';
      final r = resolveGatewayMediaUrl(
        dataUrl,
        gatewayBaseUrl: 'http://192.168.1.5:3000',
      );
      expect(r.url, dataUrl);
      expect(r.needsAuth, isFalse);
    });

    test(
      'relative URL with null gatewayBaseUrl returned as-is, no auth (cannot resolve)',
      () {
        // No base → can't resolve. Return unchanged (will fail to load, but no
        // crash) and do NOT claim auth (caller has nothing to attach).
        final r = resolveGatewayMediaUrl('/api/chat/media/outgoing/abc');
        expect(r.url, '/api/chat/media/outgoing/abc');
        expect(r.needsAuth, isFalse);
      },
    );

    test('no double slash when joining base + relative path', () {
      final r = resolveGatewayMediaUrl(
        '/api/x',
        gatewayBaseUrl: 'http://h:3000',
      );
      expect(r.url, 'http://h:3000/api/x');
    });

    test('assistant-media relative URL resolved against base', () {
      // The MEDIA: directive path (docs §4.2) — relative /__openclaw__/...
      final r = resolveGatewayMediaUrl(
        '/__openclaw__/assistant-media?source=probe.png&mediaTicket=v1.x',
        gatewayBaseUrl: 'https://gw.example.com:443',
      );
      expect(
        r.url,
        'https://gw.example.com:443/__openclaw__/assistant-media?source=probe.png&mediaTicket=v1.x',
      );
      expect(r.needsAuth, isTrue);
    });
  });

  group('GatewayMediaAuth', () {
    test('both-null default is a valid empty auth', () {
      const auth = GatewayMediaAuth(baseUrl: null, token: null);
      expect(auth.baseUrl, isNull);
      expect(auth.token, isNull);
    });

    test('carries baseUrl + token', () {
      const auth = GatewayMediaAuth(
        baseUrl: 'http://192.168.1.5:3000',
        token: 'dev-token-abc',
      );
      expect(auth.baseUrl, 'http://192.168.1.5:3000');
      expect(auth.token, 'dev-token-abc');
    });
  });
}
