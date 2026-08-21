// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CachedSessionsTable extends CachedSessions
    with TableInfo<$CachedSessionsTable, CachedSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<int> cachedAt = GeneratedColumn<int>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [sessionId, title, payload, cachedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  CachedSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedSession(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedSessionsTable createAlias(String alias) {
    return $CachedSessionsTable(attachedDatabase, alias);
  }
}

class CachedSession extends DataClass implements Insertable<CachedSession> {
  final String sessionId;
  final String title;
  final String payload;
  final int cachedAt;
  const CachedSession({
    required this.sessionId,
    required this.title,
    required this.payload,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['title'] = Variable<String>(title);
    map['payload'] = Variable<String>(payload);
    map['cached_at'] = Variable<int>(cachedAt);
    return map;
  }

  CachedSessionsCompanion toCompanion(bool nullToAbsent) {
    return CachedSessionsCompanion(
      sessionId: Value(sessionId),
      title: Value(title),
      payload: Value(payload),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedSession(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      title: serializer.fromJson<String>(json['title']),
      payload: serializer.fromJson<String>(json['payload']),
      cachedAt: serializer.fromJson<int>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'title': serializer.toJson<String>(title),
      'payload': serializer.toJson<String>(payload),
      'cachedAt': serializer.toJson<int>(cachedAt),
    };
  }

  CachedSession copyWith({
    String? sessionId,
    String? title,
    String? payload,
    int? cachedAt,
  }) => CachedSession(
    sessionId: sessionId ?? this.sessionId,
    title: title ?? this.title,
    payload: payload ?? this.payload,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedSession copyWithCompanion(CachedSessionsCompanion data) {
    return CachedSession(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      title: data.title.present ? data.title.value : this.title,
      payload: data.payload.present ? data.payload.value : this.payload,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedSession(')
          ..write('sessionId: $sessionId, ')
          ..write('title: $title, ')
          ..write('payload: $payload, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sessionId, title, payload, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedSession &&
          other.sessionId == this.sessionId &&
          other.title == this.title &&
          other.payload == this.payload &&
          other.cachedAt == this.cachedAt);
}

class CachedSessionsCompanion extends UpdateCompanion<CachedSession> {
  final Value<String> sessionId;
  final Value<String> title;
  final Value<String> payload;
  final Value<int> cachedAt;
  final Value<int> rowid;
  const CachedSessionsCompanion({
    this.sessionId = const Value.absent(),
    this.title = const Value.absent(),
    this.payload = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedSessionsCompanion.insert({
    required String sessionId,
    this.title = const Value.absent(),
    required String payload,
    required int cachedAt,
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       payload = Value(payload),
       cachedAt = Value(cachedAt);
  static Insertable<CachedSession> custom({
    Expression<String>? sessionId,
    Expression<String>? title,
    Expression<String>? payload,
    Expression<int>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (title != null) 'title': title,
      if (payload != null) 'payload': payload,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedSessionsCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? title,
    Value<String>? payload,
    Value<int>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedSessionsCompanion(
      sessionId: sessionId ?? this.sessionId,
      title: title ?? this.title,
      payload: payload ?? this.payload,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<int>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedSessionsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('title: $title, ')
          ..write('payload: $payload, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedMessagesTable extends CachedMessages
    with TableInfo<$CachedMessagesTable, CachedMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<int> cachedAt = GeneratedColumn<int>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    messageId,
    sessionId,
    payload,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {messageId};
  @override
  CachedMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedMessage(
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $CachedMessagesTable createAlias(String alias) {
    return $CachedMessagesTable(attachedDatabase, alias);
  }
}

class CachedMessage extends DataClass implements Insertable<CachedMessage> {
  final String messageId;
  final String sessionId;
  final String payload;
  final int cachedAt;
  const CachedMessage({
    required this.messageId,
    required this.sessionId,
    required this.payload,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['message_id'] = Variable<String>(messageId);
    map['session_id'] = Variable<String>(sessionId);
    map['payload'] = Variable<String>(payload);
    map['cached_at'] = Variable<int>(cachedAt);
    return map;
  }

  CachedMessagesCompanion toCompanion(bool nullToAbsent) {
    return CachedMessagesCompanion(
      messageId: Value(messageId),
      sessionId: Value(sessionId),
      payload: Value(payload),
      cachedAt: Value(cachedAt),
    );
  }

  factory CachedMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedMessage(
      messageId: serializer.fromJson<String>(json['messageId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      payload: serializer.fromJson<String>(json['payload']),
      cachedAt: serializer.fromJson<int>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'messageId': serializer.toJson<String>(messageId),
      'sessionId': serializer.toJson<String>(sessionId),
      'payload': serializer.toJson<String>(payload),
      'cachedAt': serializer.toJson<int>(cachedAt),
    };
  }

  CachedMessage copyWith({
    String? messageId,
    String? sessionId,
    String? payload,
    int? cachedAt,
  }) => CachedMessage(
    messageId: messageId ?? this.messageId,
    sessionId: sessionId ?? this.sessionId,
    payload: payload ?? this.payload,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  CachedMessage copyWithCompanion(CachedMessagesCompanion data) {
    return CachedMessage(
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      payload: data.payload.present ? data.payload.value : this.payload,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedMessage(')
          ..write('messageId: $messageId, ')
          ..write('sessionId: $sessionId, ')
          ..write('payload: $payload, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(messageId, sessionId, payload, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedMessage &&
          other.messageId == this.messageId &&
          other.sessionId == this.sessionId &&
          other.payload == this.payload &&
          other.cachedAt == this.cachedAt);
}

class CachedMessagesCompanion extends UpdateCompanion<CachedMessage> {
  final Value<String> messageId;
  final Value<String> sessionId;
  final Value<String> payload;
  final Value<int> cachedAt;
  final Value<int> rowid;
  const CachedMessagesCompanion({
    this.messageId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.payload = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedMessagesCompanion.insert({
    required String messageId,
    required String sessionId,
    required String payload,
    required int cachedAt,
    this.rowid = const Value.absent(),
  }) : messageId = Value(messageId),
       sessionId = Value(sessionId),
       payload = Value(payload),
       cachedAt = Value(cachedAt);
  static Insertable<CachedMessage> custom({
    Expression<String>? messageId,
    Expression<String>? sessionId,
    Expression<String>? payload,
    Expression<int>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (messageId != null) 'message_id': messageId,
      if (sessionId != null) 'session_id': sessionId,
      if (payload != null) 'payload': payload,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedMessagesCompanion copyWith({
    Value<String>? messageId,
    Value<String>? sessionId,
    Value<String>? payload,
    Value<int>? cachedAt,
    Value<int>? rowid,
  }) {
    return CachedMessagesCompanion(
      messageId: messageId ?? this.messageId,
      sessionId: sessionId ?? this.sessionId,
      payload: payload ?? this.payload,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<int>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedMessagesCompanion(')
          ..write('messageId: $messageId, ')
          ..write('sessionId: $sessionId, ')
          ..write('payload: $payload, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedMediaTable extends CachedMedia
    with TableInfo<$CachedMediaTable, CachedMediaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedMediaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cache_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _byteSizeMeta = const VerificationMeta(
    'byteSize',
  );
  @override
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
    'byte_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<int> cachedAt = GeneratedColumn<int>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastAccessedAtMeta = const VerificationMeta(
    'lastAccessedAt',
  );
  @override
  late final GeneratedColumn<int> lastAccessedAt = GeneratedColumn<int>(
    'last_accessed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    cacheKey,
    url,
    mimeType,
    filePath,
    byteSize,
    cachedAt,
    lastAccessedAt,
    sessionId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_media';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedMediaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cache_key')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_byteSizeMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    if (data.containsKey('last_accessed_at')) {
      context.handle(
        _lastAccessedAtMeta,
        lastAccessedAt.isAcceptableOrUnknown(
          data['last_accessed_at']!,
          _lastAccessedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastAccessedAtMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cacheKey};
  @override
  CachedMediaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedMediaData(
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cached_at'],
      )!,
      lastAccessedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_accessed_at'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
    );
  }

  @override
  $CachedMediaTable createAlias(String alias) {
    return $CachedMediaTable(attachedDatabase, alias);
  }
}

class CachedMediaData extends DataClass implements Insertable<CachedMediaData> {
  final String cacheKey;
  final String url;
  final String? mimeType;
  final String filePath;
  final int byteSize;
  final int cachedAt;
  final int lastAccessedAt;
  final String? sessionId;
  const CachedMediaData({
    required this.cacheKey,
    required this.url,
    this.mimeType,
    required this.filePath,
    required this.byteSize,
    required this.cachedAt,
    required this.lastAccessedAt,
    this.sessionId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cache_key'] = Variable<String>(cacheKey);
    map['url'] = Variable<String>(url);
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    map['file_path'] = Variable<String>(filePath);
    map['byte_size'] = Variable<int>(byteSize);
    map['cached_at'] = Variable<int>(cachedAt);
    map['last_accessed_at'] = Variable<int>(lastAccessedAt);
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    return map;
  }

  CachedMediaCompanion toCompanion(bool nullToAbsent) {
    return CachedMediaCompanion(
      cacheKey: Value(cacheKey),
      url: Value(url),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      filePath: Value(filePath),
      byteSize: Value(byteSize),
      cachedAt: Value(cachedAt),
      lastAccessedAt: Value(lastAccessedAt),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
    );
  }

  factory CachedMediaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedMediaData(
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      url: serializer.fromJson<String>(json['url']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      filePath: serializer.fromJson<String>(json['filePath']),
      byteSize: serializer.fromJson<int>(json['byteSize']),
      cachedAt: serializer.fromJson<int>(json['cachedAt']),
      lastAccessedAt: serializer.fromJson<int>(json['lastAccessedAt']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cacheKey': serializer.toJson<String>(cacheKey),
      'url': serializer.toJson<String>(url),
      'mimeType': serializer.toJson<String?>(mimeType),
      'filePath': serializer.toJson<String>(filePath),
      'byteSize': serializer.toJson<int>(byteSize),
      'cachedAt': serializer.toJson<int>(cachedAt),
      'lastAccessedAt': serializer.toJson<int>(lastAccessedAt),
      'sessionId': serializer.toJson<String?>(sessionId),
    };
  }

  CachedMediaData copyWith({
    String? cacheKey,
    String? url,
    Value<String?> mimeType = const Value.absent(),
    String? filePath,
    int? byteSize,
    int? cachedAt,
    int? lastAccessedAt,
    Value<String?> sessionId = const Value.absent(),
  }) => CachedMediaData(
    cacheKey: cacheKey ?? this.cacheKey,
    url: url ?? this.url,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    filePath: filePath ?? this.filePath,
    byteSize: byteSize ?? this.byteSize,
    cachedAt: cachedAt ?? this.cachedAt,
    lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
  );
  CachedMediaData copyWithCompanion(CachedMediaCompanion data) {
    return CachedMediaData(
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      url: data.url.present ? data.url.value : this.url,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
      lastAccessedAt: data.lastAccessedAt.present
          ? data.lastAccessedAt.value
          : this.lastAccessedAt,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedMediaData(')
          ..write('cacheKey: $cacheKey, ')
          ..write('url: $url, ')
          ..write('mimeType: $mimeType, ')
          ..write('filePath: $filePath, ')
          ..write('byteSize: $byteSize, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('lastAccessedAt: $lastAccessedAt, ')
          ..write('sessionId: $sessionId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    cacheKey,
    url,
    mimeType,
    filePath,
    byteSize,
    cachedAt,
    lastAccessedAt,
    sessionId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedMediaData &&
          other.cacheKey == this.cacheKey &&
          other.url == this.url &&
          other.mimeType == this.mimeType &&
          other.filePath == this.filePath &&
          other.byteSize == this.byteSize &&
          other.cachedAt == this.cachedAt &&
          other.lastAccessedAt == this.lastAccessedAt &&
          other.sessionId == this.sessionId);
}

class CachedMediaCompanion extends UpdateCompanion<CachedMediaData> {
  final Value<String> cacheKey;
  final Value<String> url;
  final Value<String?> mimeType;
  final Value<String> filePath;
  final Value<int> byteSize;
  final Value<int> cachedAt;
  final Value<int> lastAccessedAt;
  final Value<String?> sessionId;
  final Value<int> rowid;
  const CachedMediaCompanion({
    this.cacheKey = const Value.absent(),
    this.url = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.filePath = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.lastAccessedAt = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedMediaCompanion.insert({
    required String cacheKey,
    required String url,
    this.mimeType = const Value.absent(),
    required String filePath,
    required int byteSize,
    required int cachedAt,
    required int lastAccessedAt,
    this.sessionId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : cacheKey = Value(cacheKey),
       url = Value(url),
       filePath = Value(filePath),
       byteSize = Value(byteSize),
       cachedAt = Value(cachedAt),
       lastAccessedAt = Value(lastAccessedAt);
  static Insertable<CachedMediaData> custom({
    Expression<String>? cacheKey,
    Expression<String>? url,
    Expression<String>? mimeType,
    Expression<String>? filePath,
    Expression<int>? byteSize,
    Expression<int>? cachedAt,
    Expression<int>? lastAccessedAt,
    Expression<String>? sessionId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cacheKey != null) 'cache_key': cacheKey,
      if (url != null) 'url': url,
      if (mimeType != null) 'mime_type': mimeType,
      if (filePath != null) 'file_path': filePath,
      if (byteSize != null) 'byte_size': byteSize,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (lastAccessedAt != null) 'last_accessed_at': lastAccessedAt,
      if (sessionId != null) 'session_id': sessionId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedMediaCompanion copyWith({
    Value<String>? cacheKey,
    Value<String>? url,
    Value<String?>? mimeType,
    Value<String>? filePath,
    Value<int>? byteSize,
    Value<int>? cachedAt,
    Value<int>? lastAccessedAt,
    Value<String?>? sessionId,
    Value<int>? rowid,
  }) {
    return CachedMediaCompanion(
      cacheKey: cacheKey ?? this.cacheKey,
      url: url ?? this.url,
      mimeType: mimeType ?? this.mimeType,
      filePath: filePath ?? this.filePath,
      byteSize: byteSize ?? this.byteSize,
      cachedAt: cachedAt ?? this.cachedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      sessionId: sessionId ?? this.sessionId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<int>(cachedAt.value);
    }
    if (lastAccessedAt.present) {
      map['last_accessed_at'] = Variable<int>(lastAccessedAt.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedMediaCompanion(')
          ..write('cacheKey: $cacheKey, ')
          ..write('url: $url, ')
          ..write('mimeType: $mimeType, ')
          ..write('filePath: $filePath, ')
          ..write('byteSize: $byteSize, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('lastAccessedAt: $lastAccessedAt, ')
          ..write('sessionId: $sessionId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CachedSessionsTable cachedSessions = $CachedSessionsTable(this);
  late final $CachedMessagesTable cachedMessages = $CachedMessagesTable(this);
  late final $CachedMediaTable cachedMedia = $CachedMediaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedSessions,
    cachedMessages,
    cachedMedia,
  ];
}

typedef $$CachedSessionsTableCreateCompanionBuilder =
    CachedSessionsCompanion Function({
      required String sessionId,
      Value<String> title,
      required String payload,
      required int cachedAt,
      Value<int> rowid,
    });
typedef $$CachedSessionsTableUpdateCompanionBuilder =
    CachedSessionsCompanion Function({
      Value<String> sessionId,
      Value<String> title,
      Value<String> payload,
      Value<int> cachedAt,
      Value<int> rowid,
    });

class $$CachedSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedSessionsTable> {
  $$CachedSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedSessionsTable> {
  $$CachedSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedSessionsTable> {
  $$CachedSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedSessionsTable,
          CachedSession,
          $$CachedSessionsTableFilterComposer,
          $$CachedSessionsTableOrderingComposer,
          $$CachedSessionsTableAnnotationComposer,
          $$CachedSessionsTableCreateCompanionBuilder,
          $$CachedSessionsTableUpdateCompanionBuilder,
          (
            CachedSession,
            BaseReferences<_$AppDatabase, $CachedSessionsTable, CachedSession>,
          ),
          CachedSession,
          PrefetchHooks Function()
        > {
  $$CachedSessionsTableTableManager(
    _$AppDatabase db,
    $CachedSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedSessionsCompanion(
                sessionId: sessionId,
                title: title,
                payload: payload,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                Value<String> title = const Value.absent(),
                required String payload,
                required int cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedSessionsCompanion.insert(
                sessionId: sessionId,
                title: title,
                payload: payload,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedSessionsTable,
      CachedSession,
      $$CachedSessionsTableFilterComposer,
      $$CachedSessionsTableOrderingComposer,
      $$CachedSessionsTableAnnotationComposer,
      $$CachedSessionsTableCreateCompanionBuilder,
      $$CachedSessionsTableUpdateCompanionBuilder,
      (
        CachedSession,
        BaseReferences<_$AppDatabase, $CachedSessionsTable, CachedSession>,
      ),
      CachedSession,
      PrefetchHooks Function()
    >;
typedef $$CachedMessagesTableCreateCompanionBuilder =
    CachedMessagesCompanion Function({
      required String messageId,
      required String sessionId,
      required String payload,
      required int cachedAt,
      Value<int> rowid,
    });
typedef $$CachedMessagesTableUpdateCompanionBuilder =
    CachedMessagesCompanion Function({
      Value<String> messageId,
      Value<String> sessionId,
      Value<String> payload,
      Value<int> cachedAt,
      Value<int> rowid,
    });

class $$CachedMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $CachedMessagesTable> {
  $$CachedMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedMessagesTable> {
  $$CachedMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedMessagesTable> {
  $$CachedMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$CachedMessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedMessagesTable,
          CachedMessage,
          $$CachedMessagesTableFilterComposer,
          $$CachedMessagesTableOrderingComposer,
          $$CachedMessagesTableAnnotationComposer,
          $$CachedMessagesTableCreateCompanionBuilder,
          $$CachedMessagesTableUpdateCompanionBuilder,
          (
            CachedMessage,
            BaseReferences<_$AppDatabase, $CachedMessagesTable, CachedMessage>,
          ),
          CachedMessage,
          PrefetchHooks Function()
        > {
  $$CachedMessagesTableTableManager(
    _$AppDatabase db,
    $CachedMessagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> messageId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMessagesCompanion(
                messageId: messageId,
                sessionId: sessionId,
                payload: payload,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String messageId,
                required String sessionId,
                required String payload,
                required int cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedMessagesCompanion.insert(
                messageId: messageId,
                sessionId: sessionId,
                payload: payload,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedMessagesTable,
      CachedMessage,
      $$CachedMessagesTableFilterComposer,
      $$CachedMessagesTableOrderingComposer,
      $$CachedMessagesTableAnnotationComposer,
      $$CachedMessagesTableCreateCompanionBuilder,
      $$CachedMessagesTableUpdateCompanionBuilder,
      (
        CachedMessage,
        BaseReferences<_$AppDatabase, $CachedMessagesTable, CachedMessage>,
      ),
      CachedMessage,
      PrefetchHooks Function()
    >;
typedef $$CachedMediaTableCreateCompanionBuilder =
    CachedMediaCompanion Function({
      required String cacheKey,
      required String url,
      Value<String?> mimeType,
      required String filePath,
      required int byteSize,
      required int cachedAt,
      required int lastAccessedAt,
      Value<String?> sessionId,
      Value<int> rowid,
    });
typedef $$CachedMediaTableUpdateCompanionBuilder =
    CachedMediaCompanion Function({
      Value<String> cacheKey,
      Value<String> url,
      Value<String?> mimeType,
      Value<String> filePath,
      Value<int> byteSize,
      Value<int> cachedAt,
      Value<int> lastAccessedAt,
      Value<String?> sessionId,
      Value<int> rowid,
    });

class $$CachedMediaTableFilterComposer
    extends Composer<_$AppDatabase, $CachedMediaTable> {
  $$CachedMediaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedMediaTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedMediaTable> {
  $$CachedMediaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedMediaTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedMediaTable> {
  $$CachedMediaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);

  GeneratedColumn<int> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);

  GeneratedColumn<int> get lastAccessedAt => $composableBuilder(
    column: $table.lastAccessedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);
}

class $$CachedMediaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedMediaTable,
          CachedMediaData,
          $$CachedMediaTableFilterComposer,
          $$CachedMediaTableOrderingComposer,
          $$CachedMediaTableAnnotationComposer,
          $$CachedMediaTableCreateCompanionBuilder,
          $$CachedMediaTableUpdateCompanionBuilder,
          (
            CachedMediaData,
            BaseReferences<_$AppDatabase, $CachedMediaTable, CachedMediaData>,
          ),
          CachedMediaData,
          PrefetchHooks Function()
        > {
  $$CachedMediaTableTableManager(_$AppDatabase db, $CachedMediaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedMediaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedMediaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedMediaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> cacheKey = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<int> cachedAt = const Value.absent(),
                Value<int> lastAccessedAt = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMediaCompanion(
                cacheKey: cacheKey,
                url: url,
                mimeType: mimeType,
                filePath: filePath,
                byteSize: byteSize,
                cachedAt: cachedAt,
                lastAccessedAt: lastAccessedAt,
                sessionId: sessionId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String cacheKey,
                required String url,
                Value<String?> mimeType = const Value.absent(),
                required String filePath,
                required int byteSize,
                required int cachedAt,
                required int lastAccessedAt,
                Value<String?> sessionId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMediaCompanion.insert(
                cacheKey: cacheKey,
                url: url,
                mimeType: mimeType,
                filePath: filePath,
                byteSize: byteSize,
                cachedAt: cachedAt,
                lastAccessedAt: lastAccessedAt,
                sessionId: sessionId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedMediaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedMediaTable,
      CachedMediaData,
      $$CachedMediaTableFilterComposer,
      $$CachedMediaTableOrderingComposer,
      $$CachedMediaTableAnnotationComposer,
      $$CachedMediaTableCreateCompanionBuilder,
      $$CachedMediaTableUpdateCompanionBuilder,
      (
        CachedMediaData,
        BaseReferences<_$AppDatabase, $CachedMediaTable, CachedMediaData>,
      ),
      CachedMediaData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CachedSessionsTableTableManager get cachedSessions =>
      $$CachedSessionsTableTableManager(_db, _db.cachedSessions);
  $$CachedMessagesTableTableManager get cachedMessages =>
      $$CachedMessagesTableTableManager(_db, _db.cachedMessages);
  $$CachedMediaTableTableManager get cachedMedia =>
      $$CachedMediaTableTableManager(_db, _db.cachedMedia);
}
