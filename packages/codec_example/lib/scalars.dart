import 'package:codec/codec.dart';

part 'scalars.g.dart';

/// 原语全覆盖：String / int / double / num / bool / Object?。
@Codable()
final class Primitives {
  const Primitives({
    required this.s,
    required this.i,
    required this.d,
    required this.n,
    required this.b,
    this.any,
  });

  final String s;
  final int i;
  final double d;
  final num n;
  final bool b;
  final Object? any;

  static final Codec<Primitives> codec = _$primitivesCodec;
  factory Primitives.fromJson(Object? json) => codec.decode(json);
  Object? toJson() => codec.encode(this);
}

/// DateTime 全 5 模式（经 @CodecField(dateTime:)）。
@Codable()
final class Times {
  const Times({
    required this.local,
    required this.utc,
    required this.seconds,
    required this.millisUtc,
    required this.secondsUtc,
  });

  @CodecField(dateTime: DateTimeMode.local)
  final DateTime local;
  @CodecField(dateTime: DateTimeMode.utc)
  final DateTime utc;
  @CodecField(dateTime: DateTimeMode.seconds)
  final DateTime seconds;
  @CodecField(dateTime: DateTimeMode.millisUtc)
  final DateTime millisUtc;
  @CodecField(dateTime: DateTimeMode.secondsUtc)
  final DateTime secondsUtc;

  static final Codec<Times> codec = _$timesCodec;
  factory Times.fromJson(Object? json) => codec.decode(json);
  Object? toJson() => codec.encode(this);
}

/// 类级 snake 重命名 + includeIfNull:false；字段级 name 覆盖、默认值、required、ignore。
@Codable(fieldRename: FieldRename.snake, includeIfNull: false)
final class Account {
  const Account({
    required this.accountId,
    this.displayName,
    this.loginCount = 0,
    this.cachedToken = '',
  });

  @CodecField(required: true)
  final String accountId; // -> account_id

  @CodecField(name: 'name')
  final String? displayName; // -> name（显式覆盖 snake；null 时省略）

  @CodecField(defaultValue: 0)
  final int loginCount; // -> login_count，缺省 0

  @CodecField(ignore: true)
  final String cachedToken; // 不读不写

  static final Codec<Account> codec = _$accountCodec;
  factory Account.fromJson(Object? json) => codec.decode(json);
  Object? toJson() => codec.encode(this);
}
