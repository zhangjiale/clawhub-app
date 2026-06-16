// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class Instances extends Table with TableInfo<Instances, Instance> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Instances(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'PRIMARY KEY',
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE',
  );
  static const VerificationMeta _gatewayUrlMeta = const VerificationMeta(
    'gatewayUrl',
  );
  late final GeneratedColumn<String> gatewayUrl = GeneratedColumn<String>(
    'gateway_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _tokenRefMeta = const VerificationMeta(
    'tokenRef',
  );
  late final GeneratedColumn<String> tokenRef = GeneratedColumn<String>(
    'token_ref',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _healthStatusMeta = const VerificationMeta(
    'healthStatus',
  );
  late final GeneratedColumn<int> healthStatus = GeneratedColumn<int>(
    'health_status',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _isLocalNetworkMeta = const VerificationMeta(
    'isLocalNetwork',
  );
  late final GeneratedColumn<int> isLocalNetwork = GeneratedColumn<int>(
    'is_local_network',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _lastConnectedAtMeta = const VerificationMeta(
    'lastConnectedAt',
  );
  late final GeneratedColumn<int> lastConnectedAt = GeneratedColumn<int>(
    'last_connected_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    gatewayUrl,
    tokenRef,
    healthStatus,
    isLocalNetwork,
    lastConnectedAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'instances';
  @override
  VerificationContext validateIntegrity(
    Insertable<Instance> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('gateway_url')) {
      context.handle(
        _gatewayUrlMeta,
        gatewayUrl.isAcceptableOrUnknown(data['gateway_url']!, _gatewayUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_gatewayUrlMeta);
    }
    if (data.containsKey('token_ref')) {
      context.handle(
        _tokenRefMeta,
        tokenRef.isAcceptableOrUnknown(data['token_ref']!, _tokenRefMeta),
      );
    } else if (isInserting) {
      context.missing(_tokenRefMeta);
    }
    if (data.containsKey('health_status')) {
      context.handle(
        _healthStatusMeta,
        healthStatus.isAcceptableOrUnknown(
          data['health_status']!,
          _healthStatusMeta,
        ),
      );
    }
    if (data.containsKey('is_local_network')) {
      context.handle(
        _isLocalNetworkMeta,
        isLocalNetwork.isAcceptableOrUnknown(
          data['is_local_network']!,
          _isLocalNetworkMeta,
        ),
      );
    }
    if (data.containsKey('last_connected_at')) {
      context.handle(
        _lastConnectedAtMeta,
        lastConnectedAt.isAcceptableOrUnknown(
          data['last_connected_at']!,
          _lastConnectedAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Instance map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Instance(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      gatewayUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gateway_url'],
      )!,
      tokenRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}token_ref'],
      )!,
      healthStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}health_status'],
      ),
      isLocalNetwork: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_local_network'],
      ),
      lastConnectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_connected_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  Instances createAlias(String alias) {
    return Instances(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class Instance extends DataClass implements Insertable<Instance> {
  final String? id;
  final String name;
  final String gatewayUrl;
  final String tokenRef;
  final int? healthStatus;
  final int? isLocalNetwork;
  final int? lastConnectedAt;
  final int createdAt;
  const Instance({
    this.id,
    required this.name,
    required this.gatewayUrl,
    required this.tokenRef,
    this.healthStatus,
    this.isLocalNetwork,
    this.lastConnectedAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (!nullToAbsent || id != null) {
      map['id'] = Variable<String>(id);
    }
    map['name'] = Variable<String>(name);
    map['gateway_url'] = Variable<String>(gatewayUrl);
    map['token_ref'] = Variable<String>(tokenRef);
    if (!nullToAbsent || healthStatus != null) {
      map['health_status'] = Variable<int>(healthStatus);
    }
    if (!nullToAbsent || isLocalNetwork != null) {
      map['is_local_network'] = Variable<int>(isLocalNetwork);
    }
    if (!nullToAbsent || lastConnectedAt != null) {
      map['last_connected_at'] = Variable<int>(lastConnectedAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  InstancesCompanion toCompanion(bool nullToAbsent) {
    return InstancesCompanion(
      id: id == null && nullToAbsent ? const Value.absent() : Value(id),
      name: Value(name),
      gatewayUrl: Value(gatewayUrl),
      tokenRef: Value(tokenRef),
      healthStatus: healthStatus == null && nullToAbsent
          ? const Value.absent()
          : Value(healthStatus),
      isLocalNetwork: isLocalNetwork == null && nullToAbsent
          ? const Value.absent()
          : Value(isLocalNetwork),
      lastConnectedAt: lastConnectedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastConnectedAt),
      createdAt: Value(createdAt),
    );
  }

  factory Instance.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Instance(
      id: serializer.fromJson<String?>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      gatewayUrl: serializer.fromJson<String>(json['gateway_url']),
      tokenRef: serializer.fromJson<String>(json['token_ref']),
      healthStatus: serializer.fromJson<int?>(json['health_status']),
      isLocalNetwork: serializer.fromJson<int?>(json['is_local_network']),
      lastConnectedAt: serializer.fromJson<int?>(json['last_connected_at']),
      createdAt: serializer.fromJson<int>(json['created_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String?>(id),
      'name': serializer.toJson<String>(name),
      'gateway_url': serializer.toJson<String>(gatewayUrl),
      'token_ref': serializer.toJson<String>(tokenRef),
      'health_status': serializer.toJson<int?>(healthStatus),
      'is_local_network': serializer.toJson<int?>(isLocalNetwork),
      'last_connected_at': serializer.toJson<int?>(lastConnectedAt),
      'created_at': serializer.toJson<int>(createdAt),
    };
  }

  Instance copyWith({
    Value<String?> id = const Value.absent(),
    String? name,
    String? gatewayUrl,
    String? tokenRef,
    Value<int?> healthStatus = const Value.absent(),
    Value<int?> isLocalNetwork = const Value.absent(),
    Value<int?> lastConnectedAt = const Value.absent(),
    int? createdAt,
  }) => Instance(
    id: id.present ? id.value : this.id,
    name: name ?? this.name,
    gatewayUrl: gatewayUrl ?? this.gatewayUrl,
    tokenRef: tokenRef ?? this.tokenRef,
    healthStatus: healthStatus.present ? healthStatus.value : this.healthStatus,
    isLocalNetwork: isLocalNetwork.present
        ? isLocalNetwork.value
        : this.isLocalNetwork,
    lastConnectedAt: lastConnectedAt.present
        ? lastConnectedAt.value
        : this.lastConnectedAt,
    createdAt: createdAt ?? this.createdAt,
  );
  Instance copyWithCompanion(InstancesCompanion data) {
    return Instance(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      gatewayUrl: data.gatewayUrl.present
          ? data.gatewayUrl.value
          : this.gatewayUrl,
      tokenRef: data.tokenRef.present ? data.tokenRef.value : this.tokenRef,
      healthStatus: data.healthStatus.present
          ? data.healthStatus.value
          : this.healthStatus,
      isLocalNetwork: data.isLocalNetwork.present
          ? data.isLocalNetwork.value
          : this.isLocalNetwork,
      lastConnectedAt: data.lastConnectedAt.present
          ? data.lastConnectedAt.value
          : this.lastConnectedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Instance(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('gatewayUrl: $gatewayUrl, ')
          ..write('tokenRef: $tokenRef, ')
          ..write('healthStatus: $healthStatus, ')
          ..write('isLocalNetwork: $isLocalNetwork, ')
          ..write('lastConnectedAt: $lastConnectedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    gatewayUrl,
    tokenRef,
    healthStatus,
    isLocalNetwork,
    lastConnectedAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Instance &&
          other.id == this.id &&
          other.name == this.name &&
          other.gatewayUrl == this.gatewayUrl &&
          other.tokenRef == this.tokenRef &&
          other.healthStatus == this.healthStatus &&
          other.isLocalNetwork == this.isLocalNetwork &&
          other.lastConnectedAt == this.lastConnectedAt &&
          other.createdAt == this.createdAt);
}

class InstancesCompanion extends UpdateCompanion<Instance> {
  final Value<String?> id;
  final Value<String> name;
  final Value<String> gatewayUrl;
  final Value<String> tokenRef;
  final Value<int?> healthStatus;
  final Value<int?> isLocalNetwork;
  final Value<int?> lastConnectedAt;
  final Value<int> createdAt;
  final Value<int> rowid;
  const InstancesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.gatewayUrl = const Value.absent(),
    this.tokenRef = const Value.absent(),
    this.healthStatus = const Value.absent(),
    this.isLocalNetwork = const Value.absent(),
    this.lastConnectedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InstancesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String gatewayUrl,
    required String tokenRef,
    this.healthStatus = const Value.absent(),
    this.isLocalNetwork = const Value.absent(),
    this.lastConnectedAt = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       gatewayUrl = Value(gatewayUrl),
       tokenRef = Value(tokenRef),
       createdAt = Value(createdAt);
  static Insertable<Instance> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? gatewayUrl,
    Expression<String>? tokenRef,
    Expression<int>? healthStatus,
    Expression<int>? isLocalNetwork,
    Expression<int>? lastConnectedAt,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (gatewayUrl != null) 'gateway_url': gatewayUrl,
      if (tokenRef != null) 'token_ref': tokenRef,
      if (healthStatus != null) 'health_status': healthStatus,
      if (isLocalNetwork != null) 'is_local_network': isLocalNetwork,
      if (lastConnectedAt != null) 'last_connected_at': lastConnectedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InstancesCompanion copyWith({
    Value<String?>? id,
    Value<String>? name,
    Value<String>? gatewayUrl,
    Value<String>? tokenRef,
    Value<int?>? healthStatus,
    Value<int?>? isLocalNetwork,
    Value<int?>? lastConnectedAt,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return InstancesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      gatewayUrl: gatewayUrl ?? this.gatewayUrl,
      tokenRef: tokenRef ?? this.tokenRef,
      healthStatus: healthStatus ?? this.healthStatus,
      isLocalNetwork: isLocalNetwork ?? this.isLocalNetwork,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (gatewayUrl.present) {
      map['gateway_url'] = Variable<String>(gatewayUrl.value);
    }
    if (tokenRef.present) {
      map['token_ref'] = Variable<String>(tokenRef.value);
    }
    if (healthStatus.present) {
      map['health_status'] = Variable<int>(healthStatus.value);
    }
    if (isLocalNetwork.present) {
      map['is_local_network'] = Variable<int>(isLocalNetwork.value);
    }
    if (lastConnectedAt.present) {
      map['last_connected_at'] = Variable<int>(lastConnectedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InstancesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('gatewayUrl: $gatewayUrl, ')
          ..write('tokenRef: $tokenRef, ')
          ..write('healthStatus: $healthStatus, ')
          ..write('isLocalNetwork: $isLocalNetwork, ')
          ..write('lastConnectedAt: $lastConnectedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Agents extends Table with TableInfo<Agents, Agent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Agents(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta = const VerificationMeta(
    'localId',
  );
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
    'local_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'PRIMARY KEY',
  );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  late final GeneratedColumn<String> remoteId = GeneratedColumn<String>(
    'remote_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _instanceIdMeta = const VerificationMeta(
    'instanceId',
  );
  late final GeneratedColumn<String> instanceId = GeneratedColumn<String>(
    'instance_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _nicknameMeta = const VerificationMeta(
    'nickname',
  );
  late final GeneratedColumn<String> nickname = GeneratedColumn<String>(
    'nickname',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _themeColorMeta = const VerificationMeta(
    'themeColor',
  );
  late final GeneratedColumn<String> themeColor = GeneratedColumn<String>(
    'theme_color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'DEFAULT \'#007AFF\'',
    defaultValue: const CustomExpression('\'#007AFF\''),
  );
  static const VerificationMeta _quickCommandsJsonMeta = const VerificationMeta(
    'quickCommandsJson',
  );
  late final GeneratedColumn<String> quickCommandsJson =
      GeneratedColumn<String>(
        'quick_commands_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        $customConstraints: '',
      );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  late final GeneratedColumn<int> isPinned = GeneratedColumn<int>(
    'is_pinned',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [
    localId,
    remoteId,
    instanceId,
    name,
    nickname,
    avatarUrl,
    themeColor,
    quickCommandsJson,
    description,
    isPinned,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'agents';
  @override
  VerificationContext validateIntegrity(
    Insertable<Agent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(
        _localIdMeta,
        localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta),
      );
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_remoteIdMeta);
    }
    if (data.containsKey('instance_id')) {
      context.handle(
        _instanceIdMeta,
        instanceId.isAcceptableOrUnknown(data['instance_id']!, _instanceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_instanceIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('nickname')) {
      context.handle(
        _nicknameMeta,
        nickname.isAcceptableOrUnknown(data['nickname']!, _nicknameMeta),
      );
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('theme_color')) {
      context.handle(
        _themeColorMeta,
        themeColor.isAcceptableOrUnknown(data['theme_color']!, _themeColorMeta),
      );
    }
    if (data.containsKey('quick_commands_json')) {
      context.handle(
        _quickCommandsJsonMeta,
        quickCommandsJson.isAcceptableOrUnknown(
          data['quick_commands_json']!,
          _quickCommandsJsonMeta,
        ),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {instanceId, remoteId},
  ];
  @override
  Agent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Agent(
      localId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_id'],
      ),
      remoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_id'],
      )!,
      instanceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}instance_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nickname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nickname'],
      ),
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      themeColor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}theme_color'],
      ),
      quickCommandsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quick_commands_json'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_pinned'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  Agents createAlias(String alias) {
    return Agents(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'UNIQUE(instance_id, remote_id)',
    'FOREIGN KEY(instance_id)REFERENCES instances(id)ON DELETE CASCADE',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class Agent extends DataClass implements Insertable<Agent> {
  final String? localId;
  final String remoteId;
  final String instanceId;
  final String name;
  final String? nickname;
  final String? avatarUrl;
  final String? themeColor;
  final String? quickCommandsJson;
  final String? description;
  final int? isPinned;
  final int createdAt;
  const Agent({
    this.localId,
    required this.remoteId,
    required this.instanceId,
    required this.name,
    this.nickname,
    this.avatarUrl,
    this.themeColor,
    this.quickCommandsJson,
    this.description,
    this.isPinned,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (!nullToAbsent || localId != null) {
      map['local_id'] = Variable<String>(localId);
    }
    map['remote_id'] = Variable<String>(remoteId);
    map['instance_id'] = Variable<String>(instanceId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || nickname != null) {
      map['nickname'] = Variable<String>(nickname);
    }
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    if (!nullToAbsent || themeColor != null) {
      map['theme_color'] = Variable<String>(themeColor);
    }
    if (!nullToAbsent || quickCommandsJson != null) {
      map['quick_commands_json'] = Variable<String>(quickCommandsJson);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || isPinned != null) {
      map['is_pinned'] = Variable<int>(isPinned);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  AgentsCompanion toCompanion(bool nullToAbsent) {
    return AgentsCompanion(
      localId: localId == null && nullToAbsent
          ? const Value.absent()
          : Value(localId),
      remoteId: Value(remoteId),
      instanceId: Value(instanceId),
      name: Value(name),
      nickname: nickname == null && nullToAbsent
          ? const Value.absent()
          : Value(nickname),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      themeColor: themeColor == null && nullToAbsent
          ? const Value.absent()
          : Value(themeColor),
      quickCommandsJson: quickCommandsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(quickCommandsJson),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      isPinned: isPinned == null && nullToAbsent
          ? const Value.absent()
          : Value(isPinned),
      createdAt: Value(createdAt),
    );
  }

  factory Agent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Agent(
      localId: serializer.fromJson<String?>(json['local_id']),
      remoteId: serializer.fromJson<String>(json['remote_id']),
      instanceId: serializer.fromJson<String>(json['instance_id']),
      name: serializer.fromJson<String>(json['name']),
      nickname: serializer.fromJson<String?>(json['nickname']),
      avatarUrl: serializer.fromJson<String?>(json['avatar_url']),
      themeColor: serializer.fromJson<String?>(json['theme_color']),
      quickCommandsJson: serializer.fromJson<String?>(
        json['quick_commands_json'],
      ),
      description: serializer.fromJson<String?>(json['description']),
      isPinned: serializer.fromJson<int?>(json['is_pinned']),
      createdAt: serializer.fromJson<int>(json['created_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'local_id': serializer.toJson<String?>(localId),
      'remote_id': serializer.toJson<String>(remoteId),
      'instance_id': serializer.toJson<String>(instanceId),
      'name': serializer.toJson<String>(name),
      'nickname': serializer.toJson<String?>(nickname),
      'avatar_url': serializer.toJson<String?>(avatarUrl),
      'theme_color': serializer.toJson<String?>(themeColor),
      'quick_commands_json': serializer.toJson<String?>(quickCommandsJson),
      'description': serializer.toJson<String?>(description),
      'is_pinned': serializer.toJson<int?>(isPinned),
      'created_at': serializer.toJson<int>(createdAt),
    };
  }

  Agent copyWith({
    Value<String?> localId = const Value.absent(),
    String? remoteId,
    String? instanceId,
    String? name,
    Value<String?> nickname = const Value.absent(),
    Value<String?> avatarUrl = const Value.absent(),
    Value<String?> themeColor = const Value.absent(),
    Value<String?> quickCommandsJson = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<int?> isPinned = const Value.absent(),
    int? createdAt,
  }) => Agent(
    localId: localId.present ? localId.value : this.localId,
    remoteId: remoteId ?? this.remoteId,
    instanceId: instanceId ?? this.instanceId,
    name: name ?? this.name,
    nickname: nickname.present ? nickname.value : this.nickname,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    themeColor: themeColor.present ? themeColor.value : this.themeColor,
    quickCommandsJson: quickCommandsJson.present
        ? quickCommandsJson.value
        : this.quickCommandsJson,
    description: description.present ? description.value : this.description,
    isPinned: isPinned.present ? isPinned.value : this.isPinned,
    createdAt: createdAt ?? this.createdAt,
  );
  Agent copyWithCompanion(AgentsCompanion data) {
    return Agent(
      localId: data.localId.present ? data.localId.value : this.localId,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      instanceId: data.instanceId.present
          ? data.instanceId.value
          : this.instanceId,
      name: data.name.present ? data.name.value : this.name,
      nickname: data.nickname.present ? data.nickname.value : this.nickname,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      themeColor: data.themeColor.present
          ? data.themeColor.value
          : this.themeColor,
      quickCommandsJson: data.quickCommandsJson.present
          ? data.quickCommandsJson.value
          : this.quickCommandsJson,
      description: data.description.present
          ? data.description.value
          : this.description,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Agent(')
          ..write('localId: $localId, ')
          ..write('remoteId: $remoteId, ')
          ..write('instanceId: $instanceId, ')
          ..write('name: $name, ')
          ..write('nickname: $nickname, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('themeColor: $themeColor, ')
          ..write('quickCommandsJson: $quickCommandsJson, ')
          ..write('description: $description, ')
          ..write('isPinned: $isPinned, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localId,
    remoteId,
    instanceId,
    name,
    nickname,
    avatarUrl,
    themeColor,
    quickCommandsJson,
    description,
    isPinned,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Agent &&
          other.localId == this.localId &&
          other.remoteId == this.remoteId &&
          other.instanceId == this.instanceId &&
          other.name == this.name &&
          other.nickname == this.nickname &&
          other.avatarUrl == this.avatarUrl &&
          other.themeColor == this.themeColor &&
          other.quickCommandsJson == this.quickCommandsJson &&
          other.description == this.description &&
          other.isPinned == this.isPinned &&
          other.createdAt == this.createdAt);
}

class AgentsCompanion extends UpdateCompanion<Agent> {
  final Value<String?> localId;
  final Value<String> remoteId;
  final Value<String> instanceId;
  final Value<String> name;
  final Value<String?> nickname;
  final Value<String?> avatarUrl;
  final Value<String?> themeColor;
  final Value<String?> quickCommandsJson;
  final Value<String?> description;
  final Value<int?> isPinned;
  final Value<int> createdAt;
  final Value<int> rowid;
  const AgentsCompanion({
    this.localId = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.instanceId = const Value.absent(),
    this.name = const Value.absent(),
    this.nickname = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.themeColor = const Value.absent(),
    this.quickCommandsJson = const Value.absent(),
    this.description = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AgentsCompanion.insert({
    this.localId = const Value.absent(),
    required String remoteId,
    required String instanceId,
    required String name,
    this.nickname = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.themeColor = const Value.absent(),
    this.quickCommandsJson = const Value.absent(),
    this.description = const Value.absent(),
    this.isPinned = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : remoteId = Value(remoteId),
       instanceId = Value(instanceId),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<Agent> custom({
    Expression<String>? localId,
    Expression<String>? remoteId,
    Expression<String>? instanceId,
    Expression<String>? name,
    Expression<String>? nickname,
    Expression<String>? avatarUrl,
    Expression<String>? themeColor,
    Expression<String>? quickCommandsJson,
    Expression<String>? description,
    Expression<int>? isPinned,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (remoteId != null) 'remote_id': remoteId,
      if (instanceId != null) 'instance_id': instanceId,
      if (name != null) 'name': name,
      if (nickname != null) 'nickname': nickname,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (themeColor != null) 'theme_color': themeColor,
      if (quickCommandsJson != null) 'quick_commands_json': quickCommandsJson,
      if (description != null) 'description': description,
      if (isPinned != null) 'is_pinned': isPinned,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AgentsCompanion copyWith({
    Value<String?>? localId,
    Value<String>? remoteId,
    Value<String>? instanceId,
    Value<String>? name,
    Value<String?>? nickname,
    Value<String?>? avatarUrl,
    Value<String?>? themeColor,
    Value<String?>? quickCommandsJson,
    Value<String?>? description,
    Value<int?>? isPinned,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return AgentsCompanion(
      localId: localId ?? this.localId,
      remoteId: remoteId ?? this.remoteId,
      instanceId: instanceId ?? this.instanceId,
      name: name ?? this.name,
      nickname: nickname ?? this.nickname,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      themeColor: themeColor ?? this.themeColor,
      quickCommandsJson: quickCommandsJson ?? this.quickCommandsJson,
      description: description ?? this.description,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<String>(remoteId.value);
    }
    if (instanceId.present) {
      map['instance_id'] = Variable<String>(instanceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nickname.present) {
      map['nickname'] = Variable<String>(nickname.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (themeColor.present) {
      map['theme_color'] = Variable<String>(themeColor.value);
    }
    if (quickCommandsJson.present) {
      map['quick_commands_json'] = Variable<String>(quickCommandsJson.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<int>(isPinned.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AgentsCompanion(')
          ..write('localId: $localId, ')
          ..write('remoteId: $remoteId, ')
          ..write('instanceId: $instanceId, ')
          ..write('name: $name, ')
          ..write('nickname: $nickname, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('themeColor: $themeColor, ')
          ..write('quickCommandsJson: $quickCommandsJson, ')
          ..write('description: $description, ')
          ..write('isPinned: $isPinned, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Conversations extends Table with TableInfo<Conversations, Conversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Conversations(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'PRIMARY KEY',
  );
  static const VerificationMeta _agentIdMeta = const VerificationMeta(
    'agentId',
  );
  late final GeneratedColumn<String> agentId = GeneratedColumn<String>(
    'agent_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _instanceIdMeta = const VerificationMeta(
    'instanceId',
  );
  late final GeneratedColumn<String> instanceId = GeneratedColumn<String>(
    'instance_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _lastMessageIdMeta = const VerificationMeta(
    'lastMessageId',
  );
  late final GeneratedColumn<String> lastMessageId = GeneratedColumn<String>(
    'last_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _lastMessagePreviewMeta =
      const VerificationMeta('lastMessagePreview');
  late final GeneratedColumn<String> lastMessagePreview =
      GeneratedColumn<String>(
        'last_message_preview',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        $customConstraints: '',
      );
  static const VerificationMeta _lastMessageTimeMeta = const VerificationMeta(
    'lastMessageTime',
  );
  late final GeneratedColumn<int> lastMessageTime = GeneratedColumn<int>(
    'last_message_time',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _lastMessageRoleMeta = const VerificationMeta(
    'lastMessageRole',
  );
  late final GeneratedColumn<int> lastMessageRole = GeneratedColumn<int>(
    'last_message_role',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _isMutedMeta = const VerificationMeta(
    'isMuted',
  );
  late final GeneratedColumn<int> isMuted = GeneratedColumn<int>(
    'is_muted',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    agentId,
    instanceId,
    lastMessageId,
    lastMessagePreview,
    lastMessageTime,
    lastMessageRole,
    unreadCount,
    isMuted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Conversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('agent_id')) {
      context.handle(
        _agentIdMeta,
        agentId.isAcceptableOrUnknown(data['agent_id']!, _agentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_agentIdMeta);
    }
    if (data.containsKey('instance_id')) {
      context.handle(
        _instanceIdMeta,
        instanceId.isAcceptableOrUnknown(data['instance_id']!, _instanceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_instanceIdMeta);
    }
    if (data.containsKey('last_message_id')) {
      context.handle(
        _lastMessageIdMeta,
        lastMessageId.isAcceptableOrUnknown(
          data['last_message_id']!,
          _lastMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('last_message_preview')) {
      context.handle(
        _lastMessagePreviewMeta,
        lastMessagePreview.isAcceptableOrUnknown(
          data['last_message_preview']!,
          _lastMessagePreviewMeta,
        ),
      );
    }
    if (data.containsKey('last_message_time')) {
      context.handle(
        _lastMessageTimeMeta,
        lastMessageTime.isAcceptableOrUnknown(
          data['last_message_time']!,
          _lastMessageTimeMeta,
        ),
      );
    }
    if (data.containsKey('last_message_role')) {
      context.handle(
        _lastMessageRoleMeta,
        lastMessageRole.isAcceptableOrUnknown(
          data['last_message_role']!,
          _lastMessageRoleMeta,
        ),
      );
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    if (data.containsKey('is_muted')) {
      context.handle(
        _isMutedMeta,
        isMuted.isAcceptableOrUnknown(data['is_muted']!, _isMutedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conversation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      ),
      agentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_id'],
      )!,
      instanceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}instance_id'],
      )!,
      lastMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message_id'],
      ),
      lastMessagePreview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_message_preview'],
      ),
      lastMessageTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_message_time'],
      ),
      lastMessageRole: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_message_role'],
      ),
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      ),
      isMuted: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_muted'],
      ),
    );
  }

  @override
  Conversations createAlias(String alias) {
    return Conversations(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY(agent_id)REFERENCES agents(local_id)ON DELETE CASCADE',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class Conversation extends DataClass implements Insertable<Conversation> {
  final String? id;
  final String agentId;
  final String instanceId;
  final String? lastMessageId;
  final String? lastMessagePreview;
  final int? lastMessageTime;
  final int? lastMessageRole;
  final int? unreadCount;
  final int? isMuted;
  const Conversation({
    this.id,
    required this.agentId,
    required this.instanceId,
    this.lastMessageId,
    this.lastMessagePreview,
    this.lastMessageTime,
    this.lastMessageRole,
    this.unreadCount,
    this.isMuted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (!nullToAbsent || id != null) {
      map['id'] = Variable<String>(id);
    }
    map['agent_id'] = Variable<String>(agentId);
    map['instance_id'] = Variable<String>(instanceId);
    if (!nullToAbsent || lastMessageId != null) {
      map['last_message_id'] = Variable<String>(lastMessageId);
    }
    if (!nullToAbsent || lastMessagePreview != null) {
      map['last_message_preview'] = Variable<String>(lastMessagePreview);
    }
    if (!nullToAbsent || lastMessageTime != null) {
      map['last_message_time'] = Variable<int>(lastMessageTime);
    }
    if (!nullToAbsent || lastMessageRole != null) {
      map['last_message_role'] = Variable<int>(lastMessageRole);
    }
    if (!nullToAbsent || unreadCount != null) {
      map['unread_count'] = Variable<int>(unreadCount);
    }
    if (!nullToAbsent || isMuted != null) {
      map['is_muted'] = Variable<int>(isMuted);
    }
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      id: id == null && nullToAbsent ? const Value.absent() : Value(id),
      agentId: Value(agentId),
      instanceId: Value(instanceId),
      lastMessageId: lastMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageId),
      lastMessagePreview: lastMessagePreview == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessagePreview),
      lastMessageTime: lastMessageTime == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageTime),
      lastMessageRole: lastMessageRole == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageRole),
      unreadCount: unreadCount == null && nullToAbsent
          ? const Value.absent()
          : Value(unreadCount),
      isMuted: isMuted == null && nullToAbsent
          ? const Value.absent()
          : Value(isMuted),
    );
  }

  factory Conversation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conversation(
      id: serializer.fromJson<String?>(json['id']),
      agentId: serializer.fromJson<String>(json['agent_id']),
      instanceId: serializer.fromJson<String>(json['instance_id']),
      lastMessageId: serializer.fromJson<String?>(json['last_message_id']),
      lastMessagePreview: serializer.fromJson<String?>(
        json['last_message_preview'],
      ),
      lastMessageTime: serializer.fromJson<int?>(json['last_message_time']),
      lastMessageRole: serializer.fromJson<int?>(json['last_message_role']),
      unreadCount: serializer.fromJson<int?>(json['unread_count']),
      isMuted: serializer.fromJson<int?>(json['is_muted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String?>(id),
      'agent_id': serializer.toJson<String>(agentId),
      'instance_id': serializer.toJson<String>(instanceId),
      'last_message_id': serializer.toJson<String?>(lastMessageId),
      'last_message_preview': serializer.toJson<String?>(lastMessagePreview),
      'last_message_time': serializer.toJson<int?>(lastMessageTime),
      'last_message_role': serializer.toJson<int?>(lastMessageRole),
      'unread_count': serializer.toJson<int?>(unreadCount),
      'is_muted': serializer.toJson<int?>(isMuted),
    };
  }

  Conversation copyWith({
    Value<String?> id = const Value.absent(),
    String? agentId,
    String? instanceId,
    Value<String?> lastMessageId = const Value.absent(),
    Value<String?> lastMessagePreview = const Value.absent(),
    Value<int?> lastMessageTime = const Value.absent(),
    Value<int?> lastMessageRole = const Value.absent(),
    Value<int?> unreadCount = const Value.absent(),
    Value<int?> isMuted = const Value.absent(),
  }) => Conversation(
    id: id.present ? id.value : this.id,
    agentId: agentId ?? this.agentId,
    instanceId: instanceId ?? this.instanceId,
    lastMessageId: lastMessageId.present
        ? lastMessageId.value
        : this.lastMessageId,
    lastMessagePreview: lastMessagePreview.present
        ? lastMessagePreview.value
        : this.lastMessagePreview,
    lastMessageTime: lastMessageTime.present
        ? lastMessageTime.value
        : this.lastMessageTime,
    lastMessageRole: lastMessageRole.present
        ? lastMessageRole.value
        : this.lastMessageRole,
    unreadCount: unreadCount.present ? unreadCount.value : this.unreadCount,
    isMuted: isMuted.present ? isMuted.value : this.isMuted,
  );
  Conversation copyWithCompanion(ConversationsCompanion data) {
    return Conversation(
      id: data.id.present ? data.id.value : this.id,
      agentId: data.agentId.present ? data.agentId.value : this.agentId,
      instanceId: data.instanceId.present
          ? data.instanceId.value
          : this.instanceId,
      lastMessageId: data.lastMessageId.present
          ? data.lastMessageId.value
          : this.lastMessageId,
      lastMessagePreview: data.lastMessagePreview.present
          ? data.lastMessagePreview.value
          : this.lastMessagePreview,
      lastMessageTime: data.lastMessageTime.present
          ? data.lastMessageTime.value
          : this.lastMessageTime,
      lastMessageRole: data.lastMessageRole.present
          ? data.lastMessageRole.value
          : this.lastMessageRole,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      isMuted: data.isMuted.present ? data.isMuted.value : this.isMuted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conversation(')
          ..write('id: $id, ')
          ..write('agentId: $agentId, ')
          ..write('instanceId: $instanceId, ')
          ..write('lastMessageId: $lastMessageId, ')
          ..write('lastMessagePreview: $lastMessagePreview, ')
          ..write('lastMessageTime: $lastMessageTime, ')
          ..write('lastMessageRole: $lastMessageRole, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('isMuted: $isMuted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    agentId,
    instanceId,
    lastMessageId,
    lastMessagePreview,
    lastMessageTime,
    lastMessageRole,
    unreadCount,
    isMuted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conversation &&
          other.id == this.id &&
          other.agentId == this.agentId &&
          other.instanceId == this.instanceId &&
          other.lastMessageId == this.lastMessageId &&
          other.lastMessagePreview == this.lastMessagePreview &&
          other.lastMessageTime == this.lastMessageTime &&
          other.lastMessageRole == this.lastMessageRole &&
          other.unreadCount == this.unreadCount &&
          other.isMuted == this.isMuted);
}

class ConversationsCompanion extends UpdateCompanion<Conversation> {
  final Value<String?> id;
  final Value<String> agentId;
  final Value<String> instanceId;
  final Value<String?> lastMessageId;
  final Value<String?> lastMessagePreview;
  final Value<int?> lastMessageTime;
  final Value<int?> lastMessageRole;
  final Value<int?> unreadCount;
  final Value<int?> isMuted;
  final Value<int> rowid;
  const ConversationsCompanion({
    this.id = const Value.absent(),
    this.agentId = const Value.absent(),
    this.instanceId = const Value.absent(),
    this.lastMessageId = const Value.absent(),
    this.lastMessagePreview = const Value.absent(),
    this.lastMessageTime = const Value.absent(),
    this.lastMessageRole = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.isMuted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationsCompanion.insert({
    this.id = const Value.absent(),
    required String agentId,
    required String instanceId,
    this.lastMessageId = const Value.absent(),
    this.lastMessagePreview = const Value.absent(),
    this.lastMessageTime = const Value.absent(),
    this.lastMessageRole = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.isMuted = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : agentId = Value(agentId),
       instanceId = Value(instanceId);
  static Insertable<Conversation> custom({
    Expression<String>? id,
    Expression<String>? agentId,
    Expression<String>? instanceId,
    Expression<String>? lastMessageId,
    Expression<String>? lastMessagePreview,
    Expression<int>? lastMessageTime,
    Expression<int>? lastMessageRole,
    Expression<int>? unreadCount,
    Expression<int>? isMuted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (agentId != null) 'agent_id': agentId,
      if (instanceId != null) 'instance_id': instanceId,
      if (lastMessageId != null) 'last_message_id': lastMessageId,
      if (lastMessagePreview != null)
        'last_message_preview': lastMessagePreview,
      if (lastMessageTime != null) 'last_message_time': lastMessageTime,
      if (lastMessageRole != null) 'last_message_role': lastMessageRole,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (isMuted != null) 'is_muted': isMuted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationsCompanion copyWith({
    Value<String?>? id,
    Value<String>? agentId,
    Value<String>? instanceId,
    Value<String?>? lastMessageId,
    Value<String?>? lastMessagePreview,
    Value<int?>? lastMessageTime,
    Value<int?>? lastMessageRole,
    Value<int?>? unreadCount,
    Value<int?>? isMuted,
    Value<int>? rowid,
  }) {
    return ConversationsCompanion(
      id: id ?? this.id,
      agentId: agentId ?? this.agentId,
      instanceId: instanceId ?? this.instanceId,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastMessageRole: lastMessageRole ?? this.lastMessageRole,
      unreadCount: unreadCount ?? this.unreadCount,
      isMuted: isMuted ?? this.isMuted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (agentId.present) {
      map['agent_id'] = Variable<String>(agentId.value);
    }
    if (instanceId.present) {
      map['instance_id'] = Variable<String>(instanceId.value);
    }
    if (lastMessageId.present) {
      map['last_message_id'] = Variable<String>(lastMessageId.value);
    }
    if (lastMessagePreview.present) {
      map['last_message_preview'] = Variable<String>(lastMessagePreview.value);
    }
    if (lastMessageTime.present) {
      map['last_message_time'] = Variable<int>(lastMessageTime.value);
    }
    if (lastMessageRole.present) {
      map['last_message_role'] = Variable<int>(lastMessageRole.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (isMuted.present) {
      map['is_muted'] = Variable<int>(isMuted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('id: $id, ')
          ..write('agentId: $agentId, ')
          ..write('instanceId: $instanceId, ')
          ..write('lastMessageId: $lastMessageId, ')
          ..write('lastMessagePreview: $lastMessagePreview, ')
          ..write('lastMessageTime: $lastMessageTime, ')
          ..write('lastMessageRole: $lastMessageRole, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('isMuted: $isMuted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class Messages extends Table with TableInfo<Messages, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Messages(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _rowidMeta = const VerificationMeta('rowid');
  late final GeneratedColumn<int> rowid = GeneratedColumn<int>(
    'rowid',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'UNIQUE NOT NULL',
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'UNIQUE',
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _agentIdMeta = const VerificationMeta(
    'agentId',
  );
  late final GeneratedColumn<String> agentId = GeneratedColumn<String>(
    'agent_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  late final GeneratedColumn<int> role = GeneratedColumn<int>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _logicalClockMeta = const VerificationMeta(
    'logicalClock',
  );
  late final GeneratedColumn<int> logicalClock = GeneratedColumn<int>(
    'logical_clock',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _metadataMeta = const VerificationMeta(
    'metadata',
  );
  late final GeneratedColumn<String> metadata = GeneratedColumn<String>(
    'metadata',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    rowid,
    clientId,
    serverId,
    conversationId,
    agentId,
    role,
    content,
    type,
    status,
    logicalClock,
    timestamp,
    metadata,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('rowid')) {
      context.handle(
        _rowidMeta,
        rowid.isAcceptableOrUnknown(data['rowid']!, _rowidMeta),
      );
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientIdMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('agent_id')) {
      context.handle(
        _agentIdMeta,
        agentId.isAcceptableOrUnknown(data['agent_id']!, _agentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_agentIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('logical_clock')) {
      context.handle(
        _logicalClockMeta,
        logicalClock.isAcceptableOrUnknown(
          data['logical_clock']!,
          _logicalClockMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_logicalClockMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('metadata')) {
      context.handle(
        _metadataMeta,
        metadata.isAcceptableOrUnknown(data['metadata']!, _metadataMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {rowid};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      rowid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rowid'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      agentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}role'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      ),
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}type'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status'],
      )!,
      logicalClock: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}logical_clock'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp'],
      )!,
      metadata: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata'],
      ),
    );
  }

  @override
  Messages createAlias(String alias) {
    return Messages(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY(conversation_id)REFERENCES conversations(id)ON DELETE CASCADE',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class Message extends DataClass implements Insertable<Message> {
  final int rowid;
  final String clientId;
  final String? serverId;
  final String conversationId;
  final String agentId;
  final int role;
  final String? content;
  final int type;
  final int status;
  final int logicalClock;
  final int timestamp;
  final String? metadata;
  const Message({
    required this.rowid,
    required this.clientId,
    this.serverId,
    required this.conversationId,
    required this.agentId,
    required this.role,
    this.content,
    required this.type,
    required this.status,
    required this.logicalClock,
    required this.timestamp,
    this.metadata,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['rowid'] = Variable<int>(rowid);
    map['client_id'] = Variable<String>(clientId);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['conversation_id'] = Variable<String>(conversationId);
    map['agent_id'] = Variable<String>(agentId);
    map['role'] = Variable<int>(role);
    if (!nullToAbsent || content != null) {
      map['content'] = Variable<String>(content);
    }
    map['type'] = Variable<int>(type);
    map['status'] = Variable<int>(status);
    map['logical_clock'] = Variable<int>(logicalClock);
    map['timestamp'] = Variable<int>(timestamp);
    if (!nullToAbsent || metadata != null) {
      map['metadata'] = Variable<String>(metadata);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      rowid: Value(rowid),
      clientId: Value(clientId),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      conversationId: Value(conversationId),
      agentId: Value(agentId),
      role: Value(role),
      content: content == null && nullToAbsent
          ? const Value.absent()
          : Value(content),
      type: Value(type),
      status: Value(status),
      logicalClock: Value(logicalClock),
      timestamp: Value(timestamp),
      metadata: metadata == null && nullToAbsent
          ? const Value.absent()
          : Value(metadata),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      rowid: serializer.fromJson<int>(json['rowid']),
      clientId: serializer.fromJson<String>(json['client_id']),
      serverId: serializer.fromJson<String?>(json['server_id']),
      conversationId: serializer.fromJson<String>(json['conversation_id']),
      agentId: serializer.fromJson<String>(json['agent_id']),
      role: serializer.fromJson<int>(json['role']),
      content: serializer.fromJson<String?>(json['content']),
      type: serializer.fromJson<int>(json['type']),
      status: serializer.fromJson<int>(json['status']),
      logicalClock: serializer.fromJson<int>(json['logical_clock']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
      metadata: serializer.fromJson<String?>(json['metadata']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'rowid': serializer.toJson<int>(rowid),
      'client_id': serializer.toJson<String>(clientId),
      'server_id': serializer.toJson<String?>(serverId),
      'conversation_id': serializer.toJson<String>(conversationId),
      'agent_id': serializer.toJson<String>(agentId),
      'role': serializer.toJson<int>(role),
      'content': serializer.toJson<String?>(content),
      'type': serializer.toJson<int>(type),
      'status': serializer.toJson<int>(status),
      'logical_clock': serializer.toJson<int>(logicalClock),
      'timestamp': serializer.toJson<int>(timestamp),
      'metadata': serializer.toJson<String?>(metadata),
    };
  }

  Message copyWith({
    int? rowid,
    String? clientId,
    Value<String?> serverId = const Value.absent(),
    String? conversationId,
    String? agentId,
    int? role,
    Value<String?> content = const Value.absent(),
    int? type,
    int? status,
    int? logicalClock,
    int? timestamp,
    Value<String?> metadata = const Value.absent(),
  }) => Message(
    rowid: rowid ?? this.rowid,
    clientId: clientId ?? this.clientId,
    serverId: serverId.present ? serverId.value : this.serverId,
    conversationId: conversationId ?? this.conversationId,
    agentId: agentId ?? this.agentId,
    role: role ?? this.role,
    content: content.present ? content.value : this.content,
    type: type ?? this.type,
    status: status ?? this.status,
    logicalClock: logicalClock ?? this.logicalClock,
    timestamp: timestamp ?? this.timestamp,
    metadata: metadata.present ? metadata.value : this.metadata,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      rowid: data.rowid.present ? data.rowid.value : this.rowid,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      agentId: data.agentId.present ? data.agentId.value : this.agentId,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      type: data.type.present ? data.type.value : this.type,
      status: data.status.present ? data.status.value : this.status,
      logicalClock: data.logicalClock.present
          ? data.logicalClock.value
          : this.logicalClock,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      metadata: data.metadata.present ? data.metadata.value : this.metadata,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('rowid: $rowid, ')
          ..write('clientId: $clientId, ')
          ..write('serverId: $serverId, ')
          ..write('conversationId: $conversationId, ')
          ..write('agentId: $agentId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('type: $type, ')
          ..write('status: $status, ')
          ..write('logicalClock: $logicalClock, ')
          ..write('timestamp: $timestamp, ')
          ..write('metadata: $metadata')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    rowid,
    clientId,
    serverId,
    conversationId,
    agentId,
    role,
    content,
    type,
    status,
    logicalClock,
    timestamp,
    metadata,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.rowid == this.rowid &&
          other.clientId == this.clientId &&
          other.serverId == this.serverId &&
          other.conversationId == this.conversationId &&
          other.agentId == this.agentId &&
          other.role == this.role &&
          other.content == this.content &&
          other.type == this.type &&
          other.status == this.status &&
          other.logicalClock == this.logicalClock &&
          other.timestamp == this.timestamp &&
          other.metadata == this.metadata);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<int> rowid;
  final Value<String> clientId;
  final Value<String?> serverId;
  final Value<String> conversationId;
  final Value<String> agentId;
  final Value<int> role;
  final Value<String?> content;
  final Value<int> type;
  final Value<int> status;
  final Value<int> logicalClock;
  final Value<int> timestamp;
  final Value<String?> metadata;
  const MessagesCompanion({
    this.rowid = const Value.absent(),
    this.clientId = const Value.absent(),
    this.serverId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.agentId = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.type = const Value.absent(),
    this.status = const Value.absent(),
    this.logicalClock = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.metadata = const Value.absent(),
  });
  MessagesCompanion.insert({
    this.rowid = const Value.absent(),
    required String clientId,
    this.serverId = const Value.absent(),
    required String conversationId,
    required String agentId,
    required int role,
    this.content = const Value.absent(),
    required int type,
    required int status,
    required int logicalClock,
    required int timestamp,
    this.metadata = const Value.absent(),
  }) : clientId = Value(clientId),
       conversationId = Value(conversationId),
       agentId = Value(agentId),
       role = Value(role),
       type = Value(type),
       status = Value(status),
       logicalClock = Value(logicalClock),
       timestamp = Value(timestamp);
  static Insertable<Message> custom({
    Expression<int>? rowid,
    Expression<String>? clientId,
    Expression<String>? serverId,
    Expression<String>? conversationId,
    Expression<String>? agentId,
    Expression<int>? role,
    Expression<String>? content,
    Expression<int>? type,
    Expression<int>? status,
    Expression<int>? logicalClock,
    Expression<int>? timestamp,
    Expression<String>? metadata,
  }) {
    return RawValuesInsertable({
      if (rowid != null) 'rowid': rowid,
      if (clientId != null) 'client_id': clientId,
      if (serverId != null) 'server_id': serverId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (agentId != null) 'agent_id': agentId,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (type != null) 'type': type,
      if (status != null) 'status': status,
      if (logicalClock != null) 'logical_clock': logicalClock,
      if (timestamp != null) 'timestamp': timestamp,
      if (metadata != null) 'metadata': metadata,
    });
  }

  MessagesCompanion copyWith({
    Value<int>? rowid,
    Value<String>? clientId,
    Value<String?>? serverId,
    Value<String>? conversationId,
    Value<String>? agentId,
    Value<int>? role,
    Value<String?>? content,
    Value<int>? type,
    Value<int>? status,
    Value<int>? logicalClock,
    Value<int>? timestamp,
    Value<String?>? metadata,
  }) {
    return MessagesCompanion(
      rowid: rowid ?? this.rowid,
      clientId: clientId ?? this.clientId,
      serverId: serverId ?? this.serverId,
      conversationId: conversationId ?? this.conversationId,
      agentId: agentId ?? this.agentId,
      role: role ?? this.role,
      content: content ?? this.content,
      type: type ?? this.type,
      status: status ?? this.status,
      logicalClock: logicalClock ?? this.logicalClock,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (agentId.present) {
      map['agent_id'] = Variable<String>(agentId.value);
    }
    if (role.present) {
      map['role'] = Variable<int>(role.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (logicalClock.present) {
      map['logical_clock'] = Variable<int>(logicalClock.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    if (metadata.present) {
      map['metadata'] = Variable<String>(metadata.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('rowid: $rowid, ')
          ..write('clientId: $clientId, ')
          ..write('serverId: $serverId, ')
          ..write('conversationId: $conversationId, ')
          ..write('agentId: $agentId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('type: $type, ')
          ..write('status: $status, ')
          ..write('logicalClock: $logicalClock, ')
          ..write('timestamp: $timestamp, ')
          ..write('metadata: $metadata')
          ..write(')'))
        .toString();
  }
}

class ToolCalls extends Table with TableInfo<ToolCalls, ToolCall> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ToolCalls(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'PRIMARY KEY',
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _toolNameMeta = const VerificationMeta(
    'toolName',
  );
  late final GeneratedColumn<String> toolName = GeneratedColumn<String>(
    'tool_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _inputArgsMeta = const VerificationMeta(
    'inputArgs',
  );
  late final GeneratedColumn<String> inputArgs = GeneratedColumn<String>(
    'input_args',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _outputResultMeta = const VerificationMeta(
    'outputResult',
  );
  late final GeneratedColumn<String> outputResult = GeneratedColumn<String>(
    'output_result',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
    'started_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  late final GeneratedColumn<int> endedAt = GeneratedColumn<int>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    messageId,
    toolName,
    status,
    inputArgs,
    outputResult,
    startedAt,
    endedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tool_calls';
  @override
  VerificationContext validateIntegrity(
    Insertable<ToolCall> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('tool_name')) {
      context.handle(
        _toolNameMeta,
        toolName.isAcceptableOrUnknown(data['tool_name']!, _toolNameMeta),
      );
    } else if (isInserting) {
      context.missing(_toolNameMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('input_args')) {
      context.handle(
        _inputArgsMeta,
        inputArgs.isAcceptableOrUnknown(data['input_args']!, _inputArgsMeta),
      );
    }
    if (data.containsKey('output_result')) {
      context.handle(
        _outputResultMeta,
        outputResult.isAcceptableOrUnknown(
          data['output_result']!,
          _outputResultMeta,
        ),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ToolCall map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ToolCall(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      ),
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      toolName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tool_name'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status'],
      )!,
      inputArgs: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}input_args'],
      ),
      outputResult: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}output_result'],
      ),
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at'],
      ),
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ended_at'],
      ),
    );
  }

  @override
  ToolCalls createAlias(String alias) {
    return ToolCalls(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY(message_id)REFERENCES messages(client_id)ON DELETE CASCADE',
  ];
  @override
  bool get dontWriteConstraints => true;
}

class ToolCall extends DataClass implements Insertable<ToolCall> {
  final String? id;
  final String messageId;
  final String toolName;
  final int status;
  final String? inputArgs;
  final String? outputResult;
  final int? startedAt;
  final int? endedAt;
  const ToolCall({
    this.id,
    required this.messageId,
    required this.toolName,
    required this.status,
    this.inputArgs,
    this.outputResult,
    this.startedAt,
    this.endedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (!nullToAbsent || id != null) {
      map['id'] = Variable<String>(id);
    }
    map['message_id'] = Variable<String>(messageId);
    map['tool_name'] = Variable<String>(toolName);
    map['status'] = Variable<int>(status);
    if (!nullToAbsent || inputArgs != null) {
      map['input_args'] = Variable<String>(inputArgs);
    }
    if (!nullToAbsent || outputResult != null) {
      map['output_result'] = Variable<String>(outputResult);
    }
    if (!nullToAbsent || startedAt != null) {
      map['started_at'] = Variable<int>(startedAt);
    }
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<int>(endedAt);
    }
    return map;
  }

  ToolCallsCompanion toCompanion(bool nullToAbsent) {
    return ToolCallsCompanion(
      id: id == null && nullToAbsent ? const Value.absent() : Value(id),
      messageId: Value(messageId),
      toolName: Value(toolName),
      status: Value(status),
      inputArgs: inputArgs == null && nullToAbsent
          ? const Value.absent()
          : Value(inputArgs),
      outputResult: outputResult == null && nullToAbsent
          ? const Value.absent()
          : Value(outputResult),
      startedAt: startedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
    );
  }

  factory ToolCall.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ToolCall(
      id: serializer.fromJson<String?>(json['id']),
      messageId: serializer.fromJson<String>(json['message_id']),
      toolName: serializer.fromJson<String>(json['tool_name']),
      status: serializer.fromJson<int>(json['status']),
      inputArgs: serializer.fromJson<String?>(json['input_args']),
      outputResult: serializer.fromJson<String?>(json['output_result']),
      startedAt: serializer.fromJson<int?>(json['started_at']),
      endedAt: serializer.fromJson<int?>(json['ended_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String?>(id),
      'message_id': serializer.toJson<String>(messageId),
      'tool_name': serializer.toJson<String>(toolName),
      'status': serializer.toJson<int>(status),
      'input_args': serializer.toJson<String?>(inputArgs),
      'output_result': serializer.toJson<String?>(outputResult),
      'started_at': serializer.toJson<int?>(startedAt),
      'ended_at': serializer.toJson<int?>(endedAt),
    };
  }

  ToolCall copyWith({
    Value<String?> id = const Value.absent(),
    String? messageId,
    String? toolName,
    int? status,
    Value<String?> inputArgs = const Value.absent(),
    Value<String?> outputResult = const Value.absent(),
    Value<int?> startedAt = const Value.absent(),
    Value<int?> endedAt = const Value.absent(),
  }) => ToolCall(
    id: id.present ? id.value : this.id,
    messageId: messageId ?? this.messageId,
    toolName: toolName ?? this.toolName,
    status: status ?? this.status,
    inputArgs: inputArgs.present ? inputArgs.value : this.inputArgs,
    outputResult: outputResult.present ? outputResult.value : this.outputResult,
    startedAt: startedAt.present ? startedAt.value : this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
  );
  ToolCall copyWithCompanion(ToolCallsCompanion data) {
    return ToolCall(
      id: data.id.present ? data.id.value : this.id,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      toolName: data.toolName.present ? data.toolName.value : this.toolName,
      status: data.status.present ? data.status.value : this.status,
      inputArgs: data.inputArgs.present ? data.inputArgs.value : this.inputArgs,
      outputResult: data.outputResult.present
          ? data.outputResult.value
          : this.outputResult,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ToolCall(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('toolName: $toolName, ')
          ..write('status: $status, ')
          ..write('inputArgs: $inputArgs, ')
          ..write('outputResult: $outputResult, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    messageId,
    toolName,
    status,
    inputArgs,
    outputResult,
    startedAt,
    endedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ToolCall &&
          other.id == this.id &&
          other.messageId == this.messageId &&
          other.toolName == this.toolName &&
          other.status == this.status &&
          other.inputArgs == this.inputArgs &&
          other.outputResult == this.outputResult &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt);
}

class ToolCallsCompanion extends UpdateCompanion<ToolCall> {
  final Value<String?> id;
  final Value<String> messageId;
  final Value<String> toolName;
  final Value<int> status;
  final Value<String?> inputArgs;
  final Value<String?> outputResult;
  final Value<int?> startedAt;
  final Value<int?> endedAt;
  final Value<int> rowid;
  const ToolCallsCompanion({
    this.id = const Value.absent(),
    this.messageId = const Value.absent(),
    this.toolName = const Value.absent(),
    this.status = const Value.absent(),
    this.inputArgs = const Value.absent(),
    this.outputResult = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ToolCallsCompanion.insert({
    this.id = const Value.absent(),
    required String messageId,
    required String toolName,
    required int status,
    this.inputArgs = const Value.absent(),
    this.outputResult = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : messageId = Value(messageId),
       toolName = Value(toolName),
       status = Value(status);
  static Insertable<ToolCall> custom({
    Expression<String>? id,
    Expression<String>? messageId,
    Expression<String>? toolName,
    Expression<int>? status,
    Expression<String>? inputArgs,
    Expression<String>? outputResult,
    Expression<int>? startedAt,
    Expression<int>? endedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (messageId != null) 'message_id': messageId,
      if (toolName != null) 'tool_name': toolName,
      if (status != null) 'status': status,
      if (inputArgs != null) 'input_args': inputArgs,
      if (outputResult != null) 'output_result': outputResult,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ToolCallsCompanion copyWith({
    Value<String?>? id,
    Value<String>? messageId,
    Value<String>? toolName,
    Value<int>? status,
    Value<String?>? inputArgs,
    Value<String?>? outputResult,
    Value<int?>? startedAt,
    Value<int?>? endedAt,
    Value<int>? rowid,
  }) {
    return ToolCallsCompanion(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      toolName: toolName ?? this.toolName,
      status: status ?? this.status,
      inputArgs: inputArgs ?? this.inputArgs,
      outputResult: outputResult ?? this.outputResult,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (toolName.present) {
      map['tool_name'] = Variable<String>(toolName.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (inputArgs.present) {
      map['input_args'] = Variable<String>(inputArgs.value);
    }
    if (outputResult.present) {
      map['output_result'] = Variable<String>(outputResult.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<int>(endedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ToolCallsCompanion(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('toolName: $toolName, ')
          ..write('status: $status, ')
          ..write('inputArgs: $inputArgs, ')
          ..write('outputResult: $outputResult, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final Instances instances = Instances(this);
  late final Agents agents = Agents(this);
  late final Conversations conversations = Conversations(this);
  late final Messages messages = Messages(this);
  late final ToolCalls toolCalls = ToolCalls(this);
  late final Index idxInstancesStatus = Index(
    'idx_instances_status',
    'CREATE INDEX idx_instances_status ON instances (health_status)',
  );
  late final Index idxAgentsInstance = Index(
    'idx_agents_instance',
    'CREATE INDEX idx_agents_instance ON agents (instance_id)',
  );
  late final Index idxAgentsRemote = Index(
    'idx_agents_remote',
    'CREATE INDEX idx_agents_remote ON agents (instance_id, remote_id)',
  );
  late final Index idxAgentsPinName = Index(
    'idx_agents_pin_name',
    'CREATE INDEX idx_agents_pin_name ON agents (instance_id, is_pinned DESC, name ASC)',
  );
  late final Index idxConvTime = Index(
    'idx_conv_time',
    'CREATE INDEX idx_conv_time ON conversations (last_message_time DESC)',
  );
  late final Index idxConvAgent = Index(
    'idx_conv_agent',
    'CREATE INDEX idx_conv_agent ON conversations (agent_id)',
  );
  late final Index idxMsgsConvTime = Index(
    'idx_msgs_conv_time',
    'CREATE INDEX idx_msgs_conv_time ON messages (conversation_id, timestamp DESC)',
  );
  late final Index idxMsgsServer = Index(
    'idx_msgs_server',
    'CREATE INDEX idx_msgs_server ON messages (server_id)',
  );
  late final Index idxMsgsAgent = Index(
    'idx_msgs_agent',
    'CREATE INDEX idx_msgs_agent ON messages (agent_id)',
  );
  late final Index idxMsgsStatus = Index(
    'idx_msgs_status',
    'CREATE INDEX idx_msgs_status ON messages (status)',
  );
  late final Index idxMsgsConvClock = Index(
    'idx_msgs_conv_clock',
    'CREATE INDEX idx_msgs_conv_clock ON messages (conversation_id, logical_clock DESC)',
  );
  late final Index idxToolCallsMsg = Index(
    'idx_tool_calls_msg',
    'CREATE INDEX idx_tool_calls_msg ON tool_calls (message_id)',
  );
  Selectable<Instance> getAllInstances() {
    return customSelect(
      'SELECT * FROM instances ORDER BY last_connected_at DESC',
      variables: [],
      readsFrom: {instances},
    ).asyncMap(instances.mapFromRow);
  }

  Selectable<Instance> getInstanceById(String? id) {
    return customSelect(
      'SELECT * FROM instances WHERE id = ?1',
      variables: [Variable<String>(id)],
      readsFrom: {instances},
    ).asyncMap(instances.mapFromRow);
  }

  Selectable<int> checkNameExists(String name, String? excludeId) {
    return customSelect(
      'SELECT COUNT(*) AS cnt FROM instances WHERE name = ?1 AND(COALESCE(?2, \'\') = \'\' OR id != ?2)',
      variables: [Variable<String>(name), Variable<String>(excludeId)],
      readsFrom: {instances},
    ).map((QueryRow row) => row.read<int>('cnt'));
  }

  Future<int> upsertInstance(
    String? id,
    String name,
    String gatewayUrl,
    String tokenRef,
    int? healthStatus,
    int? isLocalNetwork,
    int? lastConnectedAt,
    int createdAt,
  ) {
    return customInsert(
      'INSERT OR REPLACE INTO instances (id, name, gateway_url, token_ref, health_status, is_local_network, last_connected_at, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)',
      variables: [
        Variable<String>(id),
        Variable<String>(name),
        Variable<String>(gatewayUrl),
        Variable<String>(tokenRef),
        Variable<int>(healthStatus),
        Variable<int>(isLocalNetwork),
        Variable<int>(lastConnectedAt),
        Variable<int>(createdAt),
      ],
      updates: {instances},
    );
  }

  Future<int> deleteInstanceById(String? id) {
    return customUpdate(
      'DELETE FROM instances WHERE id = ?1',
      variables: [Variable<String>(id)],
      updates: {instances},
      updateKind: UpdateKind.delete,
    );
  }

  Future<int> updateInstanceHealthStatus(int? status, String? id) {
    return customUpdate(
      'UPDATE instances SET health_status = ?1 WHERE id = ?2',
      variables: [Variable<int>(status), Variable<String>(id)],
      updates: {instances},
      updateKind: UpdateKind.update,
    );
  }

  Future<int> updateInstanceLastConnectedAt(int? timestamp, String? id) {
    return customUpdate(
      'UPDATE instances SET last_connected_at = ?1 WHERE id = ?2',
      variables: [Variable<int>(timestamp), Variable<String>(id)],
      updates: {instances},
      updateKind: UpdateKind.update,
    );
  }

  Future<int> batchUpdateStatusByNetwork(int? status, int? isLocalNetwork) {
    return customUpdate(
      'UPDATE instances SET health_status = ?1 WHERE is_local_network = ?2',
      variables: [Variable<int>(status), Variable<int>(isLocalNetwork)],
      updates: {instances},
      updateKind: UpdateKind.update,
    );
  }

  Selectable<Agent> getAgentsByInstance(String instanceId) {
    return customSelect(
      'SELECT * FROM agents WHERE instance_id = ?1 ORDER BY is_pinned DESC, name ASC',
      variables: [Variable<String>(instanceId)],
      readsFrom: {agents},
    ).asyncMap(agents.mapFromRow);
  }

  Selectable<Agent> getAllAgents() {
    return customSelect(
      'SELECT * FROM agents ORDER BY is_pinned DESC, name ASC',
      variables: [],
      readsFrom: {agents},
    ).asyncMap(agents.mapFromRow);
  }

  Selectable<Agent> getAgentByLocalId(String? localId) {
    return customSelect(
      'SELECT * FROM agents WHERE local_id = ?1',
      variables: [Variable<String>(localId)],
      readsFrom: {agents},
    ).asyncMap(agents.mapFromRow);
  }

  Selectable<Agent> findAgentByCompositeKey(
    String instanceId,
    String remoteId,
  ) {
    return customSelect(
      'SELECT * FROM agents WHERE instance_id = ?1 AND remote_id = ?2',
      variables: [Variable<String>(instanceId), Variable<String>(remoteId)],
      readsFrom: {agents},
    ).asyncMap(agents.mapFromRow);
  }

  Future<int> insertAgent(
    String? localId,
    String remoteId,
    String instanceId,
    String name,
    String? nickname,
    String? avatarUrl,
    String? themeColor,
    String? quickCommandsJson,
    String? description,
    int? isPinned,
    int createdAt,
  ) {
    return customInsert(
      'INSERT INTO agents (local_id, remote_id, instance_id, name, nickname, avatar_url, theme_color, quick_commands_json, description, is_pinned, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)',
      variables: [
        Variable<String>(localId),
        Variable<String>(remoteId),
        Variable<String>(instanceId),
        Variable<String>(name),
        Variable<String>(nickname),
        Variable<String>(avatarUrl),
        Variable<String>(themeColor),
        Variable<String>(quickCommandsJson),
        Variable<String>(description),
        Variable<int>(isPinned),
        Variable<int>(createdAt),
      ],
      updates: {agents},
    );
  }

  Future<int> updateAgentFromGateway(
    String name,
    String? description,
    String? localId,
  ) {
    return customUpdate(
      'UPDATE agents SET name = ?1, description = ?2 WHERE local_id = ?3',
      variables: [
        Variable<String>(name),
        Variable<String>(description),
        Variable<String>(localId),
      ],
      updates: {agents},
      updateKind: UpdateKind.update,
    );
  }

  Future<int> updateAgentQuickCommands(String? json, String? localId) {
    return customUpdate(
      'UPDATE agents SET quick_commands_json = ?1 WHERE local_id = ?2',
      variables: [Variable<String>(json), Variable<String>(localId)],
      updates: {agents},
      updateKind: UpdateKind.update,
    );
  }

  Future<int> toggleAgentPin(String? localId) {
    return customUpdate(
      'UPDATE agents SET is_pinned = CASE WHEN is_pinned = 1 THEN 0 ELSE 1 END WHERE local_id = ?1',
      variables: [Variable<String>(localId)],
      updates: {agents},
      updateKind: UpdateKind.update,
    );
  }

  Future<int> deleteAgentsByInstanceId(String instanceId) {
    return customUpdate(
      'DELETE FROM agents WHERE instance_id = ?1',
      variables: [Variable<String>(instanceId)],
      updates: {agents},
      updateKind: UpdateKind.delete,
    );
  }

  Selectable<Conversation> getConversationById(String? id) {
    return customSelect(
      'SELECT * FROM conversations WHERE id = ?1',
      variables: [Variable<String>(id)],
      readsFrom: {conversations},
    ).asyncMap(conversations.mapFromRow);
  }

  Selectable<Conversation> getAllConversationsWithMessages() {
    return customSelect(
      'SELECT * FROM conversations WHERE last_message_time > 0 ORDER BY last_message_time DESC',
      variables: [],
      readsFrom: {conversations},
    ).asyncMap(conversations.mapFromRow);
  }

  Future<int> insertConversation(
    String? id,
    String agentId,
    String instanceId,
    String? lastMessageId,
    String? lastMessagePreview,
    int? lastMessageTime,
    int? lastMessageRole,
    int? unreadCount,
    int? isMuted,
  ) {
    return customInsert(
      'INSERT OR IGNORE INTO conversations (id, agent_id, instance_id, last_message_id, last_message_preview, last_message_time, last_message_role, unread_count, is_muted) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)',
      variables: [
        Variable<String>(id),
        Variable<String>(agentId),
        Variable<String>(instanceId),
        Variable<String>(lastMessageId),
        Variable<String>(lastMessagePreview),
        Variable<int>(lastMessageTime),
        Variable<int>(lastMessageRole),
        Variable<int>(unreadCount),
        Variable<int>(isMuted),
      ],
      updates: {conversations},
    );
  }

  Future<int> updateConversationLastMessage(
    String? messageId,
    String? preview,
    int? timestamp,
    int? role,
    String? conversationId,
  ) {
    return customUpdate(
      'UPDATE conversations SET last_message_id = ?1, last_message_preview = ?2, last_message_time = ?3, last_message_role = ?4 WHERE id = ?5',
      variables: [
        Variable<String>(messageId),
        Variable<String>(preview),
        Variable<int>(timestamp),
        Variable<int>(role),
        Variable<String>(conversationId),
      ],
      updates: {conversations},
      updateKind: UpdateKind.update,
    );
  }

  Future<int> incrementConversationUnread(double count, String? id) {
    return customUpdate(
      'UPDATE conversations SET unread_count = unread_count + ?1 WHERE id = ?2',
      variables: [Variable<double>(count), Variable<String>(id)],
      updates: {conversations},
      updateKind: UpdateKind.update,
    );
  }

  Future<int> clearConversationUnread(String? id) {
    return customUpdate(
      'UPDATE conversations SET unread_count = 0 WHERE id = ?1',
      variables: [Variable<String>(id)],
      updates: {conversations},
      updateKind: UpdateKind.update,
    );
  }

  Future<int> toggleConversationMute(String? id) {
    return customUpdate(
      'UPDATE conversations SET is_muted = CASE WHEN is_muted = 1 THEN 0 ELSE 1 END WHERE id = ?1',
      variables: [Variable<String>(id)],
      updates: {conversations},
      updateKind: UpdateKind.update,
    );
  }

  Future<int> deleteConversationsByInstanceId(String instanceId) {
    return customUpdate(
      'DELETE FROM conversations WHERE instance_id = ?1',
      variables: [Variable<String>(instanceId)],
      updates: {conversations},
      updateKind: UpdateKind.delete,
    );
  }

  Selectable<Message> getMessageByClientId(String clientId) {
    return customSelect(
      'SELECT * FROM messages WHERE client_id = ?1',
      variables: [Variable<String>(clientId)],
      readsFrom: {messages},
    ).asyncMap(messages.mapFromRow);
  }

  Selectable<Message> getMessageByServerId(String? serverId) {
    return customSelect(
      'SELECT * FROM messages WHERE server_id = ?1',
      variables: [Variable<String>(serverId)],
      readsFrom: {messages},
    ).asyncMap(messages.mapFromRow);
  }

  Selectable<Message> getMessagesByConversationFirst(
    String conversationId,
    int limit,
  ) {
    return customSelect(
      'SELECT * FROM messages WHERE conversation_id = ?1 ORDER BY logical_clock DESC LIMIT ?2',
      variables: [Variable<String>(conversationId), Variable<int>(limit)],
      readsFrom: {messages},
    ).asyncMap(messages.mapFromRow);
  }

  Selectable<Message> getMessagesByConversationBefore(
    String conversationId,
    String before,
    int limit,
  ) {
    return customSelect(
      'SELECT * FROM messages WHERE conversation_id = ?1 AND logical_clock < (SELECT logical_clock FROM messages WHERE client_id = ?2) ORDER BY logical_clock DESC LIMIT ?3',
      variables: [
        Variable<String>(conversationId),
        Variable<String>(before),
        Variable<int>(limit),
      ],
      readsFrom: {messages},
    ).asyncMap(messages.mapFromRow);
  }

  Selectable<Message> getAllMessagesByConversationAsc(String conversationId) {
    return customSelect(
      'SELECT * FROM messages WHERE conversation_id = ?1 ORDER BY logical_clock ASC',
      variables: [Variable<String>(conversationId)],
      readsFrom: {messages},
    ).asyncMap(messages.mapFromRow);
  }

  Future<int> insertMessage(
    String clientId,
    String? serverId,
    String conversationId,
    String agentId,
    int role,
    String? content,
    int type,
    int status,
    int logicalClock,
    int timestamp,
    String? metadata,
  ) {
    return customInsert(
      'INSERT INTO messages (client_id, server_id, conversation_id, agent_id, role, content, type, status, logical_clock, timestamp, metadata) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)',
      variables: [
        Variable<String>(clientId),
        Variable<String>(serverId),
        Variable<String>(conversationId),
        Variable<String>(agentId),
        Variable<int>(role),
        Variable<String>(content),
        Variable<int>(type),
        Variable<int>(status),
        Variable<int>(logicalClock),
        Variable<int>(timestamp),
        Variable<String>(metadata),
      ],
      updates: {messages},
    );
  }

  Future<int> updateMessageStatusById(int status, String clientId) {
    return customUpdate(
      'UPDATE messages SET status = ?1 WHERE client_id = ?2',
      variables: [Variable<int>(status), Variable<String>(clientId)],
      updates: {messages},
      updateKind: UpdateKind.update,
    );
  }

  Future<int> bindMessageServerId(
    String? serverId,
    int status,
    String clientId,
  ) {
    return customUpdate(
      'UPDATE messages SET server_id = ?1, status = ?2 WHERE client_id = ?3',
      variables: [
        Variable<String>(serverId),
        Variable<int>(status),
        Variable<String>(clientId),
      ],
      updates: {messages},
      updateKind: UpdateKind.update,
    );
  }

  Selectable<Message> getOutboxMessages(String agentId) {
    return customSelect(
      'SELECT * FROM messages WHERE agent_id = ?1 AND status IN (1, 5)',
      variables: [Variable<String>(agentId)],
      readsFrom: {messages},
    ).asyncMap(messages.mapFromRow);
  }

  Selectable<Message> searchMessages(String query, int limit, int offset) {
    return customSelect(
      'SELECT m.* FROM messages AS m JOIN messages_fts AS fts ON m."rowid" = fts."rowid" WHERE messages_fts MATCH ?1 ORDER BY m.timestamp DESC LIMIT ?2 OFFSET ?3',
      variables: [
        Variable<String>(query),
        Variable<int>(limit),
        Variable<int>(offset),
      ],
      readsFrom: {messages},
    ).asyncMap(messages.mapFromRow);
  }

  Selectable<int> getMessageCountByAgent(String agentId) {
    return customSelect(
      'SELECT COUNT(*) AS cnt FROM messages WHERE agent_id = ?1',
      variables: [Variable<String>(agentId)],
      readsFrom: {messages},
    ).map((QueryRow row) => row.read<int>('cnt'));
  }

  Future<int> deleteOldMessagesByAgent(String agentId, int keep) {
    return customUpdate(
      'DELETE FROM messages WHERE agent_id = ?1 AND "rowid" NOT IN (SELECT "rowid" FROM messages WHERE agent_id = ?1 ORDER BY timestamp DESC LIMIT ?2)',
      variables: [Variable<String>(agentId), Variable<int>(keep)],
      updates: {messages},
      updateKind: UpdateKind.delete,
    );
  }

  Future<int> deleteMessageByClientId(String clientId) {
    return customUpdate(
      'DELETE FROM messages WHERE client_id = ?1',
      variables: [Variable<String>(clientId)],
      updates: {messages},
      updateKind: UpdateKind.delete,
    );
  }

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    instances,
    agents,
    conversations,
    messages,
    toolCalls,
    idxInstancesStatus,
    idxAgentsInstance,
    idxAgentsRemote,
    idxAgentsPinName,
    idxConvTime,
    idxConvAgent,
    idxMsgsConvTime,
    idxMsgsServer,
    idxMsgsAgent,
    idxMsgsStatus,
    idxMsgsConvClock,
    idxToolCallsMsg,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'instances',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('agents', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'agents',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('conversations', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'conversations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('messages', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('tool_calls', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $InstancesCreateCompanionBuilder =
    InstancesCompanion Function({
      Value<String?> id,
      required String name,
      required String gatewayUrl,
      required String tokenRef,
      Value<int?> healthStatus,
      Value<int?> isLocalNetwork,
      Value<int?> lastConnectedAt,
      required int createdAt,
      Value<int> rowid,
    });
typedef $InstancesUpdateCompanionBuilder =
    InstancesCompanion Function({
      Value<String?> id,
      Value<String> name,
      Value<String> gatewayUrl,
      Value<String> tokenRef,
      Value<int?> healthStatus,
      Value<int?> isLocalNetwork,
      Value<int?> lastConnectedAt,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $InstancesFilterComposer extends Composer<_$AppDatabase, Instances> {
  $InstancesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gatewayUrl => $composableBuilder(
    column: $table.gatewayUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tokenRef => $composableBuilder(
    column: $table.tokenRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get healthStatus => $composableBuilder(
    column: $table.healthStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get isLocalNetwork => $composableBuilder(
    column: $table.isLocalNetwork,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $InstancesOrderingComposer extends Composer<_$AppDatabase, Instances> {
  $InstancesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gatewayUrl => $composableBuilder(
    column: $table.gatewayUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tokenRef => $composableBuilder(
    column: $table.tokenRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get healthStatus => $composableBuilder(
    column: $table.healthStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get isLocalNetwork => $composableBuilder(
    column: $table.isLocalNetwork,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $InstancesAnnotationComposer extends Composer<_$AppDatabase, Instances> {
  $InstancesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get gatewayUrl => $composableBuilder(
    column: $table.gatewayUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tokenRef =>
      $composableBuilder(column: $table.tokenRef, builder: (column) => column);

  GeneratedColumn<int> get healthStatus => $composableBuilder(
    column: $table.healthStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get isLocalNetwork => $composableBuilder(
    column: $table.isLocalNetwork,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $InstancesTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Instances,
          Instance,
          $InstancesFilterComposer,
          $InstancesOrderingComposer,
          $InstancesAnnotationComposer,
          $InstancesCreateCompanionBuilder,
          $InstancesUpdateCompanionBuilder,
          (Instance, BaseReferences<_$AppDatabase, Instances, Instance>),
          Instance,
          PrefetchHooks Function()
        > {
  $InstancesTableManager(_$AppDatabase db, Instances table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $InstancesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $InstancesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $InstancesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String?> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> gatewayUrl = const Value.absent(),
                Value<String> tokenRef = const Value.absent(),
                Value<int?> healthStatus = const Value.absent(),
                Value<int?> isLocalNetwork = const Value.absent(),
                Value<int?> lastConnectedAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InstancesCompanion(
                id: id,
                name: name,
                gatewayUrl: gatewayUrl,
                tokenRef: tokenRef,
                healthStatus: healthStatus,
                isLocalNetwork: isLocalNetwork,
                lastConnectedAt: lastConnectedAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String?> id = const Value.absent(),
                required String name,
                required String gatewayUrl,
                required String tokenRef,
                Value<int?> healthStatus = const Value.absent(),
                Value<int?> isLocalNetwork = const Value.absent(),
                Value<int?> lastConnectedAt = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => InstancesCompanion.insert(
                id: id,
                name: name,
                gatewayUrl: gatewayUrl,
                tokenRef: tokenRef,
                healthStatus: healthStatus,
                isLocalNetwork: isLocalNetwork,
                lastConnectedAt: lastConnectedAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $InstancesProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Instances,
      Instance,
      $InstancesFilterComposer,
      $InstancesOrderingComposer,
      $InstancesAnnotationComposer,
      $InstancesCreateCompanionBuilder,
      $InstancesUpdateCompanionBuilder,
      (Instance, BaseReferences<_$AppDatabase, Instances, Instance>),
      Instance,
      PrefetchHooks Function()
    >;
typedef $AgentsCreateCompanionBuilder =
    AgentsCompanion Function({
      Value<String?> localId,
      required String remoteId,
      required String instanceId,
      required String name,
      Value<String?> nickname,
      Value<String?> avatarUrl,
      Value<String?> themeColor,
      Value<String?> quickCommandsJson,
      Value<String?> description,
      Value<int?> isPinned,
      required int createdAt,
      Value<int> rowid,
    });
typedef $AgentsUpdateCompanionBuilder =
    AgentsCompanion Function({
      Value<String?> localId,
      Value<String> remoteId,
      Value<String> instanceId,
      Value<String> name,
      Value<String?> nickname,
      Value<String?> avatarUrl,
      Value<String?> themeColor,
      Value<String?> quickCommandsJson,
      Value<String?> description,
      Value<int?> isPinned,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $AgentsFilterComposer extends Composer<_$AppDatabase, Agents> {
  $AgentsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get instanceId => $composableBuilder(
    column: $table.instanceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get themeColor => $composableBuilder(
    column: $table.themeColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quickCommandsJson => $composableBuilder(
    column: $table.quickCommandsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $AgentsOrderingComposer extends Composer<_$AppDatabase, Agents> {
  $AgentsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localId => $composableBuilder(
    column: $table.localId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get instanceId => $composableBuilder(
    column: $table.instanceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nickname => $composableBuilder(
    column: $table.nickname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get themeColor => $composableBuilder(
    column: $table.themeColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quickCommandsJson => $composableBuilder(
    column: $table.quickCommandsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $AgentsAnnotationComposer extends Composer<_$AppDatabase, Agents> {
  $AgentsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumn<String> get instanceId => $composableBuilder(
    column: $table.instanceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nickname =>
      $composableBuilder(column: $table.nickname, builder: (column) => column);

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<String> get themeColor => $composableBuilder(
    column: $table.themeColor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get quickCommandsJson => $composableBuilder(
    column: $table.quickCommandsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $AgentsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Agents,
          Agent,
          $AgentsFilterComposer,
          $AgentsOrderingComposer,
          $AgentsAnnotationComposer,
          $AgentsCreateCompanionBuilder,
          $AgentsUpdateCompanionBuilder,
          (Agent, BaseReferences<_$AppDatabase, Agents, Agent>),
          Agent,
          PrefetchHooks Function()
        > {
  $AgentsTableManager(_$AppDatabase db, Agents table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $AgentsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $AgentsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $AgentsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String?> localId = const Value.absent(),
                Value<String> remoteId = const Value.absent(),
                Value<String> instanceId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nickname = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> themeColor = const Value.absent(),
                Value<String?> quickCommandsJson = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<int?> isPinned = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AgentsCompanion(
                localId: localId,
                remoteId: remoteId,
                instanceId: instanceId,
                name: name,
                nickname: nickname,
                avatarUrl: avatarUrl,
                themeColor: themeColor,
                quickCommandsJson: quickCommandsJson,
                description: description,
                isPinned: isPinned,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String?> localId = const Value.absent(),
                required String remoteId,
                required String instanceId,
                required String name,
                Value<String?> nickname = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> themeColor = const Value.absent(),
                Value<String?> quickCommandsJson = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<int?> isPinned = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => AgentsCompanion.insert(
                localId: localId,
                remoteId: remoteId,
                instanceId: instanceId,
                name: name,
                nickname: nickname,
                avatarUrl: avatarUrl,
                themeColor: themeColor,
                quickCommandsJson: quickCommandsJson,
                description: description,
                isPinned: isPinned,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $AgentsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Agents,
      Agent,
      $AgentsFilterComposer,
      $AgentsOrderingComposer,
      $AgentsAnnotationComposer,
      $AgentsCreateCompanionBuilder,
      $AgentsUpdateCompanionBuilder,
      (Agent, BaseReferences<_$AppDatabase, Agents, Agent>),
      Agent,
      PrefetchHooks Function()
    >;
typedef $ConversationsCreateCompanionBuilder =
    ConversationsCompanion Function({
      Value<String?> id,
      required String agentId,
      required String instanceId,
      Value<String?> lastMessageId,
      Value<String?> lastMessagePreview,
      Value<int?> lastMessageTime,
      Value<int?> lastMessageRole,
      Value<int?> unreadCount,
      Value<int?> isMuted,
      Value<int> rowid,
    });
typedef $ConversationsUpdateCompanionBuilder =
    ConversationsCompanion Function({
      Value<String?> id,
      Value<String> agentId,
      Value<String> instanceId,
      Value<String?> lastMessageId,
      Value<String?> lastMessagePreview,
      Value<int?> lastMessageTime,
      Value<int?> lastMessageRole,
      Value<int?> unreadCount,
      Value<int?> isMuted,
      Value<int> rowid,
    });

class $ConversationsFilterComposer
    extends Composer<_$AppDatabase, Conversations> {
  $ConversationsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentId => $composableBuilder(
    column: $table.agentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get instanceId => $composableBuilder(
    column: $table.instanceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessageId => $composableBuilder(
    column: $table.lastMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastMessageTime => $composableBuilder(
    column: $table.lastMessageTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastMessageRole => $composableBuilder(
    column: $table.lastMessageRole,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get isMuted => $composableBuilder(
    column: $table.isMuted,
    builder: (column) => ColumnFilters(column),
  );
}

class $ConversationsOrderingComposer
    extends Composer<_$AppDatabase, Conversations> {
  $ConversationsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentId => $composableBuilder(
    column: $table.agentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get instanceId => $composableBuilder(
    column: $table.instanceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessageId => $composableBuilder(
    column: $table.lastMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastMessageTime => $composableBuilder(
    column: $table.lastMessageTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastMessageRole => $composableBuilder(
    column: $table.lastMessageRole,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get isMuted => $composableBuilder(
    column: $table.isMuted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $ConversationsAnnotationComposer
    extends Composer<_$AppDatabase, Conversations> {
  $ConversationsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get agentId =>
      $composableBuilder(column: $table.agentId, builder: (column) => column);

  GeneratedColumn<String> get instanceId => $composableBuilder(
    column: $table.instanceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastMessageId => $composableBuilder(
    column: $table.lastMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastMessagePreview => $composableBuilder(
    column: $table.lastMessagePreview,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastMessageTime => $composableBuilder(
    column: $table.lastMessageTime,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastMessageRole => $composableBuilder(
    column: $table.lastMessageRole,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get isMuted =>
      $composableBuilder(column: $table.isMuted, builder: (column) => column);
}

class $ConversationsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Conversations,
          Conversation,
          $ConversationsFilterComposer,
          $ConversationsOrderingComposer,
          $ConversationsAnnotationComposer,
          $ConversationsCreateCompanionBuilder,
          $ConversationsUpdateCompanionBuilder,
          (
            Conversation,
            BaseReferences<_$AppDatabase, Conversations, Conversation>,
          ),
          Conversation,
          PrefetchHooks Function()
        > {
  $ConversationsTableManager(_$AppDatabase db, Conversations table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ConversationsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ConversationsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ConversationsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String?> id = const Value.absent(),
                Value<String> agentId = const Value.absent(),
                Value<String> instanceId = const Value.absent(),
                Value<String?> lastMessageId = const Value.absent(),
                Value<String?> lastMessagePreview = const Value.absent(),
                Value<int?> lastMessageTime = const Value.absent(),
                Value<int?> lastMessageRole = const Value.absent(),
                Value<int?> unreadCount = const Value.absent(),
                Value<int?> isMuted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion(
                id: id,
                agentId: agentId,
                instanceId: instanceId,
                lastMessageId: lastMessageId,
                lastMessagePreview: lastMessagePreview,
                lastMessageTime: lastMessageTime,
                lastMessageRole: lastMessageRole,
                unreadCount: unreadCount,
                isMuted: isMuted,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String?> id = const Value.absent(),
                required String agentId,
                required String instanceId,
                Value<String?> lastMessageId = const Value.absent(),
                Value<String?> lastMessagePreview = const Value.absent(),
                Value<int?> lastMessageTime = const Value.absent(),
                Value<int?> lastMessageRole = const Value.absent(),
                Value<int?> unreadCount = const Value.absent(),
                Value<int?> isMuted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion.insert(
                id: id,
                agentId: agentId,
                instanceId: instanceId,
                lastMessageId: lastMessageId,
                lastMessagePreview: lastMessagePreview,
                lastMessageTime: lastMessageTime,
                lastMessageRole: lastMessageRole,
                unreadCount: unreadCount,
                isMuted: isMuted,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $ConversationsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Conversations,
      Conversation,
      $ConversationsFilterComposer,
      $ConversationsOrderingComposer,
      $ConversationsAnnotationComposer,
      $ConversationsCreateCompanionBuilder,
      $ConversationsUpdateCompanionBuilder,
      (
        Conversation,
        BaseReferences<_$AppDatabase, Conversations, Conversation>,
      ),
      Conversation,
      PrefetchHooks Function()
    >;
typedef $MessagesCreateCompanionBuilder =
    MessagesCompanion Function({
      Value<int> rowid,
      required String clientId,
      Value<String?> serverId,
      required String conversationId,
      required String agentId,
      required int role,
      Value<String?> content,
      required int type,
      required int status,
      required int logicalClock,
      required int timestamp,
      Value<String?> metadata,
    });
typedef $MessagesUpdateCompanionBuilder =
    MessagesCompanion Function({
      Value<int> rowid,
      Value<String> clientId,
      Value<String?> serverId,
      Value<String> conversationId,
      Value<String> agentId,
      Value<int> role,
      Value<String?> content,
      Value<int> type,
      Value<int> status,
      Value<int> logicalClock,
      Value<int> timestamp,
      Value<String?> metadata,
    });

class $MessagesFilterComposer extends Composer<_$AppDatabase, Messages> {
  $MessagesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get rowid => $composableBuilder(
    column: $table.rowid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentId => $composableBuilder(
    column: $table.agentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get logicalClock => $composableBuilder(
    column: $table.logicalClock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadata => $composableBuilder(
    column: $table.metadata,
    builder: (column) => ColumnFilters(column),
  );
}

class $MessagesOrderingComposer extends Composer<_$AppDatabase, Messages> {
  $MessagesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get rowid => $composableBuilder(
    column: $table.rowid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentId => $composableBuilder(
    column: $table.agentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get logicalClock => $composableBuilder(
    column: $table.logicalClock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadata => $composableBuilder(
    column: $table.metadata,
    builder: (column) => ColumnOrderings(column),
  );
}

class $MessagesAnnotationComposer extends Composer<_$AppDatabase, Messages> {
  $MessagesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get rowid =>
      $composableBuilder(column: $table.rowid, builder: (column) => column);

  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get agentId =>
      $composableBuilder(column: $table.agentId, builder: (column) => column);

  GeneratedColumn<int> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get logicalClock => $composableBuilder(
    column: $table.logicalClock,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get metadata =>
      $composableBuilder(column: $table.metadata, builder: (column) => column);
}

class $MessagesTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          Messages,
          Message,
          $MessagesFilterComposer,
          $MessagesOrderingComposer,
          $MessagesAnnotationComposer,
          $MessagesCreateCompanionBuilder,
          $MessagesUpdateCompanionBuilder,
          (Message, BaseReferences<_$AppDatabase, Messages, Message>),
          Message,
          PrefetchHooks Function()
        > {
  $MessagesTableManager(_$AppDatabase db, Messages table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MessagesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MessagesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MessagesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> rowid = const Value.absent(),
                Value<String> clientId = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> agentId = const Value.absent(),
                Value<int> role = const Value.absent(),
                Value<String?> content = const Value.absent(),
                Value<int> type = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<int> logicalClock = const Value.absent(),
                Value<int> timestamp = const Value.absent(),
                Value<String?> metadata = const Value.absent(),
              }) => MessagesCompanion(
                rowid: rowid,
                clientId: clientId,
                serverId: serverId,
                conversationId: conversationId,
                agentId: agentId,
                role: role,
                content: content,
                type: type,
                status: status,
                logicalClock: logicalClock,
                timestamp: timestamp,
                metadata: metadata,
              ),
          createCompanionCallback:
              ({
                Value<int> rowid = const Value.absent(),
                required String clientId,
                Value<String?> serverId = const Value.absent(),
                required String conversationId,
                required String agentId,
                required int role,
                Value<String?> content = const Value.absent(),
                required int type,
                required int status,
                required int logicalClock,
                required int timestamp,
                Value<String?> metadata = const Value.absent(),
              }) => MessagesCompanion.insert(
                rowid: rowid,
                clientId: clientId,
                serverId: serverId,
                conversationId: conversationId,
                agentId: agentId,
                role: role,
                content: content,
                type: type,
                status: status,
                logicalClock: logicalClock,
                timestamp: timestamp,
                metadata: metadata,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $MessagesProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      Messages,
      Message,
      $MessagesFilterComposer,
      $MessagesOrderingComposer,
      $MessagesAnnotationComposer,
      $MessagesCreateCompanionBuilder,
      $MessagesUpdateCompanionBuilder,
      (Message, BaseReferences<_$AppDatabase, Messages, Message>),
      Message,
      PrefetchHooks Function()
    >;
typedef $ToolCallsCreateCompanionBuilder =
    ToolCallsCompanion Function({
      Value<String?> id,
      required String messageId,
      required String toolName,
      required int status,
      Value<String?> inputArgs,
      Value<String?> outputResult,
      Value<int?> startedAt,
      Value<int?> endedAt,
      Value<int> rowid,
    });
typedef $ToolCallsUpdateCompanionBuilder =
    ToolCallsCompanion Function({
      Value<String?> id,
      Value<String> messageId,
      Value<String> toolName,
      Value<int> status,
      Value<String?> inputArgs,
      Value<String?> outputResult,
      Value<int?> startedAt,
      Value<int?> endedAt,
      Value<int> rowid,
    });

class $ToolCallsFilterComposer extends Composer<_$AppDatabase, ToolCalls> {
  $ToolCallsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toolName => $composableBuilder(
    column: $table.toolName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inputArgs => $composableBuilder(
    column: $table.inputArgs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outputResult => $composableBuilder(
    column: $table.outputResult,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $ToolCallsOrderingComposer extends Composer<_$AppDatabase, ToolCalls> {
  $ToolCallsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toolName => $composableBuilder(
    column: $table.toolName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inputArgs => $composableBuilder(
    column: $table.inputArgs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outputResult => $composableBuilder(
    column: $table.outputResult,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $ToolCallsAnnotationComposer extends Composer<_$AppDatabase, ToolCalls> {
  $ToolCallsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get toolName =>
      $composableBuilder(column: $table.toolName, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get inputArgs =>
      $composableBuilder(column: $table.inputArgs, builder: (column) => column);

  GeneratedColumn<String> get outputResult => $composableBuilder(
    column: $table.outputResult,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);
}

class $ToolCallsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          ToolCalls,
          ToolCall,
          $ToolCallsFilterComposer,
          $ToolCallsOrderingComposer,
          $ToolCallsAnnotationComposer,
          $ToolCallsCreateCompanionBuilder,
          $ToolCallsUpdateCompanionBuilder,
          (ToolCall, BaseReferences<_$AppDatabase, ToolCalls, ToolCall>),
          ToolCall,
          PrefetchHooks Function()
        > {
  $ToolCallsTableManager(_$AppDatabase db, ToolCalls table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ToolCallsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ToolCallsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ToolCallsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String?> id = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String> toolName = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<String?> inputArgs = const Value.absent(),
                Value<String?> outputResult = const Value.absent(),
                Value<int?> startedAt = const Value.absent(),
                Value<int?> endedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ToolCallsCompanion(
                id: id,
                messageId: messageId,
                toolName: toolName,
                status: status,
                inputArgs: inputArgs,
                outputResult: outputResult,
                startedAt: startedAt,
                endedAt: endedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String?> id = const Value.absent(),
                required String messageId,
                required String toolName,
                required int status,
                Value<String?> inputArgs = const Value.absent(),
                Value<String?> outputResult = const Value.absent(),
                Value<int?> startedAt = const Value.absent(),
                Value<int?> endedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ToolCallsCompanion.insert(
                id: id,
                messageId: messageId,
                toolName: toolName,
                status: status,
                inputArgs: inputArgs,
                outputResult: outputResult,
                startedAt: startedAt,
                endedAt: endedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $ToolCallsProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      ToolCalls,
      ToolCall,
      $ToolCallsFilterComposer,
      $ToolCallsOrderingComposer,
      $ToolCallsAnnotationComposer,
      $ToolCallsCreateCompanionBuilder,
      $ToolCallsUpdateCompanionBuilder,
      (ToolCall, BaseReferences<_$AppDatabase, ToolCalls, ToolCall>),
      ToolCall,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $InstancesTableManager get instances =>
      $InstancesTableManager(_db, _db.instances);
  $AgentsTableManager get agents => $AgentsTableManager(_db, _db.agents);
  $ConversationsTableManager get conversations =>
      $ConversationsTableManager(_db, _db.conversations);
  $MessagesTableManager get messages =>
      $MessagesTableManager(_db, _db.messages);
  $ToolCallsTableManager get toolCalls =>
      $ToolCallsTableManager(_db, _db.toolCalls);
}
