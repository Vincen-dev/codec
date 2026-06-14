import 'package:codec/codec.dart';

part 'nested.g.dart';

/// 自定义 codec：decode 转小写、encode 转大写。被 @CodecField(codec:) 引用。
/// 同时验证 DecodeOutcome / DecodeContext / DecodeOk / WrongType 等是公开可用的。
const _shoutCodec = _ShoutCodec();

final class _ShoutCodec extends Codec<String> {
  const _ShoutCodec();

  @override
  DecodeOutcome<String> doDecode(DecodeContext ctx) {
    final v = ctx.value;
    if (v is String) return DecodeOk(v.toLowerCase());
    return ctx.fail(const WrongType('String'));
  }

  @override
  Object? doEncode(String value) => value.toUpperCase();
}

@Codable()
final class Child {
  const Child({required this.label});

  final String label;

  static final Codec<Child> codec = _$childCodec;
  factory Child.fromJson(Object? json) => codec.decode(json);
  Object? toJson() => codec.encode(this);
}

@Codable()
final class Parent {
  const Parent({required this.child, required this.code});

  final Child child; // 嵌套 @Codable 模型

  @CodecField(codec: '_shoutCodec')
  final String code; // 自定义 codec 引用

  static final Codec<Parent> codec = _$parentCodec;
  factory Parent.fromJson(Object? json) => codec.decode(json);
  Object? toJson() => codec.encode(this);
}

/// 自引用递归 → 生成 Codec.lazy(() => Tree.codec)。
@Codable()
final class Tree {
  const Tree({required this.value, this.children = const []});

  final int value;
  final List<Tree> children;

  static final Codec<Tree> codec = _$treeCodec;
  factory Tree.fromJson(Object? json) => codec.decode(json);
  Object? toJson() => codec.encode(this);
}
