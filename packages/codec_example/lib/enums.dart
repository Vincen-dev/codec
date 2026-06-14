import 'package:codec/codec.dart';

part 'enums.g.dart';

/// 无 @CodecEnum：被模型字段引用时 inline Codec.enumByName(.name)。
enum Plain { alpha, beta }

/// @CodecEnum 按 .name。
@CodecEnum()
enum Named {
  red,
  green;

  static final Codec<Named> codec = _$namedCodec;
}

/// @CodecEnum(valueField:) int code。
@CodecEnum(valueField: 'code')
enum Currency {
  hkd(344),
  jpy(392);

  const Currency(this.code);
  final int code;

  static final Codec<Currency> codec = _$currencyCodec;
}

/// @CodecValue String（含双向 toJson）。
@CodecEnum()
enum Channel {
  @CodecValue('QR')
  qr,
  @CodecValue('NFC')
  nfc;

  static final Codec<Channel> codec = _$channelCodec;
}

/// @CodecValue int。
@CodecEnum()
enum Level {
  @CodecValue(1)
  low,
  @CodecValue(5)
  high;

  static final Codec<Level> codec = _$levelCodec;
}

/// core 层枚举（无序列化注解），由字段级 enumValueField 映射。
enum Region {
  hk(81),
  jp(99);

  const Region(this.code);
  final int code;
}

@Codable()
final class Enums {
  const Enums({
    required this.plain,
    required this.named,
    required this.currency,
    required this.channel,
    required this.level,
    required this.region,
  });

  final Plain plain;
  final Named named;
  final Currency currency;
  final Channel channel;
  final Level level;

  @CodecField(enumValueField: 'code', unknownEnumValue: Region.hk)
  final Region region;

  static final Codec<Enums> codec = _$enumsCodec;
  factory Enums.fromJson(Object? json) => codec.decode(json);
  Object? toJson() => codec.encode(this);
}
