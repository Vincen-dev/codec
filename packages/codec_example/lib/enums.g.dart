// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enums.dart';

// **************************************************************************
// CodableGenerator
// **************************************************************************

// Region.code 字段级映射（Enums.region 专用）。
final Codec<Region> _$enumsRegionEnumCodec = Codec.enumOf<Region, int>(
  Codec.integer,
  {
    Region.hk.code: Region.hk,
    Region.jp.code: Region.jp,
  },
  unknownFallback: Region.hk,
);

final Codec<Enums> _$enumsCodec = Codec.object<Enums>(
  (b) => Enums(
    plain: b.required<Plain>('plain', Codec.enumByName(const {'alpha': Plain.alpha, 'beta': Plain.beta})),
    named: b.required<Named>('named', Named.codec),
    currency: b.required<Currency>('currency', Currency.codec),
    channel: b.required<Channel>('channel', Channel.codec),
    level: b.required<Level>('level', Level.codec),
    region: b.required<Region>('region', _$enumsRegionEnumCodec),
  ),
  encode: (v) => {
    'plain': Codec.enumByName(const {'alpha': Plain.alpha, 'beta': Plain.beta}).encode(v.plain),
    'named': Named.codec.encode(v.named),
    'currency': Currency.codec.encode(v.currency),
    'channel': Channel.codec.encode(v.channel),
    'level': Level.codec.encode(v.level),
    'region': _$enumsRegionEnumCodec.encode(v.region),
  },
);

// **************************************************************************
// CodecEnumGenerator
// **************************************************************************

// 按 .name 默认映射（Named 未挂 @CodecValue）。
final Codec<Named> _$namedCodec = Codec.enumByName(const {
  'red': Named.red,
  'green': Named.green,
});

// 按 Currency.code 字段映射。
// （Map 不带 const：enum 实例字段访问在 const 表达式里受限。）
final Codec<Currency> _$currencyCodec = Codec.enumOf<Currency, int>(
  Codec.integer,
  {
    Currency.hkd.code: Currency.hkd,
    Currency.jpy.code: Currency.jpy,
  },
);

// @CodecValue 映射（String），含双向 toJson。
final Codec<Channel> _$channelCodec = Codec.enumByName(
  const {
    'QR': Channel.qr,
    'NFC': Channel.nfc,
  },
  toJson: (e) => switch (e) {
    Channel.qr => 'QR',
    Channel.nfc => 'NFC',
  },
);

// @CodecValue 映射（int）。
final Codec<Level> _$levelCodec = Codec.enumOf<Level, int>(
  Codec.integer,
  const {
    1: Level.low,
    5: Level.high,
  },
);
