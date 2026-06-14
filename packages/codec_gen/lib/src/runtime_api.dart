/// codec_gen 发射的运行时 API 名常量——codec_gen 与 codec 运行时之间
/// 字符串契约的单一可见清单。改动 codec 公开 API 时同步此处；
/// packages/codec_example 的 e2e 测试会在不同步时编译失败（CI 拦截）。
///
/// 范围（§3 最小版）：仅 CodecResolver / _dateTimeCodecFor 的类型→codec 映射；
/// 不含 b.required/optional/optionalOr、Codec.object 等生成 DSL（有意留 inline）。
abstract final class RuntimeApi {
  static const string = 'Codec.string';
  static const integer = 'Codec.integer';
  static const number = 'Codec.number';
  static const numeric = 'Codec.numeric';
  static const boolean = 'Codec.boolean';
  static const any = 'Codec.any';

  static const dateTime = 'Codec.dateTime';
  static const dateTimeUtc = 'Codec.dateTimeUtc';
  static const dateTimeSeconds = 'Codec.dateTimeSeconds';
  static const dateTimeMillisUtc = 'Codec.dateTimeMillisUtc';
  static const dateTimeSecondsUtc = 'Codec.dateTimeSecondsUtc';

  static const enumByName = 'Codec.enumByName';
  static const enumOf = 'Codec.enumOf';
  static const mapOf = 'Codec.mapOf';
  static const lazy = 'Codec.lazy';

  static const listCall = '.list()';
  static const nullableCall = '.nullable()';
}
