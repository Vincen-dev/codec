part of '../codec.dart';

// ===========================================================================
// Object + Discriminated
//
// 与其他 codec 不同，Object 解码用 builder DSL ([FieldsReader])，需要在
// 字段失败时短路 builder——通过库内私有的 [_ObjectShortCircuit] 异常实现，
// 由 [_ObjectCodec.doDecode] 的 try/catch 捕获并转回 [DecodeFail]。
// ===========================================================================

/// builder 字段失败时短路用的内部异常。
///
/// **不暴露**给 library 外：被 [_ObjectCodec.doDecode] 捕获后转回
/// [DecodeFail]，外部最终看到的是 [DecodeException]。
class _ObjectShortCircuit implements Exception {
  const _ObjectShortCircuit(this.errors);
  final List<DecodeError> errors;
}

/// Object 解码时给 builder 用的字段读取器。
///
/// `required` / `optional` / `optionalOr` 自动追加路径、调用子 codec、
/// 在失败时短路抛 [_ObjectShortCircuit]，外层 [_ObjectCodec.doDecode]
/// catch 后转回 [DecodeFail]。
final class FieldsReader {
  FieldsReader._(this._ctx, this._map);

  final DecodeContext _ctx;
  final Map<String, dynamic> _map;

  /// 必填字段：缺失 / null / 子 codec 失败均短路。
  T required<T>(String key, Codec<T> codec) {
    final present = _map.containsKey(key);
    final raw = present ? _map[key] : null;
    final childPath = PathField(_ctx.path, key);
    if (!present) {
      throw _ObjectShortCircuit([
        DecodeError(path: childPath, kind: const MissingField()),
      ]);
    }
    if (raw == null) {
      throw _ObjectShortCircuit([
        DecodeError(path: childPath, kind: const IsNullField()),
      ]);
    }
    final out = codec.doDecode(_ctx.field(key, raw));
    return switch (out) {
      DecodeOk(:final value) => value,
      DecodeFail(:final errors) => throw _ObjectShortCircuit(errors),
    };
  }

  /// 可选字段：缺失 / null 返回 null；类型不符仍然算错（不静默降级）。
  T? optional<T>(String key, Codec<T> codec) {
    if (!_map.containsKey(key)) return null;
    final raw = _map[key];
    if (raw == null) return null;
    final out = codec.doDecode(_ctx.field(key, raw));
    return switch (out) {
      DecodeOk(:final value) => value,
      DecodeFail(:final errors) => throw _ObjectShortCircuit(errors),
    };
  }

  /// 可选字段带 fallback：仅在**字段缺失或值为 null** 时回落到 [fallback]。
  /// 类型/格式错误仍按 [optional] 一样短路报错（与 [Codec.withDefault] 同语义），
  /// 避免 schema 漂移被 fallback 静默吞掉。
  T optionalOr<T>(String key, Codec<T> codec, T fallback) =>
      optional(key, codec) ?? fallback;
}

final class _ObjectCodec<T> extends Codec<T> {
  const _ObjectCodec(this._build, this._encode);
  final T Function(FieldsReader) _build;
  final Map<String, Object?> Function(T)? _encode;

  @override
  DecodeOutcome<T> doDecode(DecodeContext ctx) {
    final v = ctx.value;
    if (v is! Map) return ctx.fail(const WrongType('Map'));
    final map = v is Map<String, dynamic> ? v : v.cast<String, dynamic>();
    final reader = FieldsReader._(ctx, map);
    try {
      return DecodeOk(_build(reader));
    } on _ObjectShortCircuit catch (e) {
      return DecodeFail<T>(e.errors);
    }
  }

  @override
  Object? doEncode(T value) {
    final fn = _encode;
    if (fn == null) {
      throw EncodeException._(
        message: 'Codec.object<$T> was created without an `encode` argument; '
            'pass `encode:` to Codec.object(...) to support toJson/encode',
        hint: '$T',
      );
    }
    return fn(value);
  }
}

final class _DiscriminatedCodec<T> extends Codec<T> {
  const _DiscriminatedCodec(this._tag, this._cases, this._encode);
  final String _tag;
  final Map<String, Codec<T>> _cases;
  final (String, Map<String, Object?>) Function(T) _encode;

  @override
  DecodeOutcome<T> doDecode(DecodeContext ctx) {
    final v = ctx.value;
    if (v is! Map) return ctx.fail(const WrongType('Map'));
    final tagValue = v[_tag];
    if (tagValue == null) {
      return ctx.field(_tag, null).fail(const MissingField());
    }
    if (tagValue is! String) {
      return ctx.field(_tag, tagValue).fail(const WrongType('String'));
    }
    final branch = _cases[tagValue];
    if (branch == null) {
      return ctx.field(_tag, tagValue).fail(
            UnknownTag(
              tagValue,
              _cases.keys.toList(growable: false),
            ),
          );
    }
    return branch.doDecode(ctx);
  }

  @override
  Object? doEncode(T value) {
    final (tag, body) = _encode(value);
    // tag 后置：若 body 内意外塞了同名 key，codec 注入的判别 tag 必定胜出
    return {...body, _tag: tag};
  }
}
