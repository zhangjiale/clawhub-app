import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/usecases/gateway_change_resolution.dart';

void main() {
  group('GatewayChangeResolution', () {
    test('values 包含 keepLocal 和 purgeLocal', () {
      expect(GatewayChangeResolution.values, hasLength(2));
      expect(
        GatewayChangeResolution.values,
        containsAll(<GatewayChangeResolution>[
          GatewayChangeResolution.keepLocal,
          GatewayChangeResolution.purgeLocal,
        ]),
      );
    });

    test('keepLocal 与 purgeLocal 不相等', () {
      expect(
        GatewayChangeResolution.keepLocal,
        isNot(equals(GatewayChangeResolution.purgeLocal)),
      );
    });
  });
}
