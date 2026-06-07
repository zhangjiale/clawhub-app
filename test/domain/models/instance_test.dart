import 'package:flutter_test/flutter_test.dart';
import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';

void main() {
  group('Instance', () {
    test('创建有效实例（内网地址自动识别）', () {
      final instance = Instance(
        id: 'inst-001',
        name: '我的MacBook',
        gatewayUrl: 'ws://192.168.1.100:18789',
        tokenRef: 'keychain_ref_abc',
      );

      expect(instance.id, 'inst-001');
      expect(instance.name, '我的MacBook');
      expect(instance.gatewayUrl, 'ws://192.168.1.100:18789');
      expect(instance.tokenRef, 'keychain_ref_abc');
      expect(instance.healthStatus, HealthStatus.unknown); // default
      expect(instance.isLocalNetwork, isTrue); // 192.168.x.x 是内网
      expect(instance.lastConnectedAt, isNull);
      expect(instance.createdAt, isNotNull);
    });

    group('名称验证', () {
      test('名称为空应抛异常', () {
        expect(
          () => Instance(
            id: 'inst-001',
            name: '',
            gatewayUrl: 'ws://192.168.1.100:18789',
            tokenRef: 'keychain_ref_abc',
          ),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('实例名称不能为空'),
          )),
        );
      });

      test('名称只有空格应抛异常', () {
        expect(
          () => Instance(
            id: 'inst-001',
            name: '   ',
            gatewayUrl: 'ws://192.168.1.100:18789',
            tokenRef: 'keychain_ref_abc',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Gateway URL 验证', () {
      test('wss:// 协议应通过校验', () {
        final instance = Instance(
          id: 'inst-002',
          name: '云服务器',
          gatewayUrl: 'wss://bj.myserver.com:18789',
          tokenRef: 'keychain_ref_def',
        );
        expect(instance.gatewayUrl, 'wss://bj.myserver.com:18789');
      });

      test('缺少端口号应抛异常', () {
        expect(
          () => Instance(
            id: 'inst-003',
            name: '错误实例',
            gatewayUrl: 'ws://192.168.1.100',
            tokenRef: 'keychain_ref_ghi',
          ),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('端口号'),
          )),
        );
      });

      test('http:// 协议应抛异常', () {
        expect(
          () => Instance(
            id: 'inst-004',
            name: '错误协议',
            gatewayUrl: 'http://192.168.1.100:18789',
            tokenRef: 'keychain_ref_jkl',
          ),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('ws:// 或 wss://'),
          )),
        );
      });

      test('空URL应抛异常', () {
        expect(
          () => Instance(
            id: 'inst-005',
            name: '空URL',
            gatewayUrl: '',
            tokenRef: 'keychain_ref_mno',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('内网 IP 检测', () {
      test('192.168.x.x 应识别为内网', () {
        final instance = Instance(
          id: 'inst-006',
          name: '内网实例',
          gatewayUrl: 'ws://192.168.1.100:18789',
          tokenRef: 'keychain_ref_pqr',
        );
        expect(instance.isLocalNetwork, isTrue);
      });

      test('10.x.x.x 应识别为内网', () {
        final instance = Instance(
          id: 'inst-007',
          name: '公司内网',
          gatewayUrl: 'ws://10.0.0.50:18789',
          tokenRef: 'keychain_ref_stu',
        );
        expect(instance.isLocalNetwork, isTrue);
      });

      test('172.16-31.x.x 应识别为内网', () {
        final instance = Instance(
          id: 'inst-008',
          name: 'Docker网络',
          gatewayUrl: 'ws://172.17.0.1:18789',
          tokenRef: 'keychain_ref_vwx',
        );
        expect(instance.isLocalNetwork, isTrue);
      });

      test('公网域名应识别为外网', () {
        final instance = Instance(
          id: 'inst-009',
          name: '云服务器',
          gatewayUrl: 'wss://bj.myserver.com:18789',
          tokenRef: 'keychain_ref_yza',
        );
        expect(instance.isLocalNetwork, isFalse);
      });
    });

    group('copyWith', () {
      test('应创建修改后的副本', () {
        final original = Instance(
          id: 'inst-010',
          name: '原名称',
          gatewayUrl: 'ws://192.168.1.100:18789',
          tokenRef: 'keychain_ref_bbb',
        );

        final updated = original.copyWith(
          name: '新名称',
          healthStatus: HealthStatus.online,
        );

        expect(updated.id, original.id);
        expect(updated.name, '新名称');
        expect(updated.healthStatus, HealthStatus.online);
        expect(updated.gatewayUrl, original.gatewayUrl); // 未修改
        expect(updated.tokenRef, original.tokenRef); // 未修改
      });
    });
  });
}
