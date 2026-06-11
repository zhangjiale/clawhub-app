import 'package:claw_hub/domain/models/instance.dart';
import 'package:claw_hub/domain/models/enums.dart';

import '../database/database.dart' as db;

/// Maps between Drift-generated [db.Instance] rows and the domain [Instance] model.
class InstanceMapper {
  const InstanceMapper._();

  /// Convert a Drift row to a domain [Instance].
  static Instance toDomain(db.Instance row) {
    final id = row.id;
    if (id == null) throw StateError('Instance row has null primary key');
    return Instance(
      id: id,
      name: row.name,
      gatewayUrl: row.gatewayUrl,
      tokenRef: row.tokenRef,
      healthStatus:
          HealthStatus.fromInt(row.healthStatus ?? 0),
      isLocalNetwork: row.isLocalNetwork == 1,
      lastConnectedAt: row.lastConnectedAt,
      createdAt: row.createdAt,
    );
  }

}
