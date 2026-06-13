part of '../codec.dart';

// ===========================================================================
// 组合子 codec
//
// 按"包裹其他 codec"的拓扑组织。除 [_LazyCodec] 因需要可变缓存使用普通
// final，其余均 const 友好。访问方式：
//   - 链式：`codec.nullable()` / `.list()` / `.refine(...)` ...
//   - 工厂：`Codec.firstOf(...)` / `Codec.lazy(...)` / `Codec.mapOf(...)` ...
// ===========================================================================

final class _NullableCodec<T> extends Codec<T?> {
  const _NullableCodec(this._inner);
  final Codec<T> _inner;

  @override
  DecodeOutcome<T?> doDecode(DecodeContext ctx) {
    if (ctx.value == null) return DecodeOk<T?>(null);
    final out = _inner.doDecode(ctx);
    return switch (out) {
      DecodeOk(:final value) => DecodeOk<T?>(value),
      DecodeFail(:final errors) => DecodeFail<T?>(errors),
    };
  }

  @override
  Object? doEncode(T? value) =>
      value == null ? null : _inner.doEncode(value);
}

final class _DefaultCodec<T> extends Codec<T> {
  const _DefaultCodec(this._inner, this._fallback);
  final Codec<T> _inner;
  final T _fallback;

  @override
  DecodeOutcome<T> doDecode(DecodeContext ctx) {
    if (ctx.value == null) return DecodeOk(_fallback);
    return _inner.doDecode(ctx);
  }

  @override
  Object? doEncode(T value) => _inner.doEncode(value);
}

/// 包装一个 codec，使其 decode/encode 出口转抛 [FormatException]（兼容模式）。
/// 仅委托内层；异常只在顶层 decode/encode 出口构造，故只有最外层的风格生效。
final class _StyledCodec<T> extends Codec<T> {
  const _StyledCodec(this._inner);
  final Codec<T> _inner;
  @override
  bool get _throwsFormat => true;
  @override
  DecodeOutcome<T> doDecode(DecodeContext ctx) => _inner.doDecode(ctx);
  @override
  Object? doEncode(T value) => _inner.doEncode(value);
}

final class _RefineCodec<T> extends Codec<T> {
  const _RefineCodec(this._inner, this._predicate, this._message);
  final Codec<T> _inner;
  final bool Function(T) _predicate;
  final String _message;

  @override
  DecodeOutcome<T> doDecode(DecodeContext ctx) {
    final out = _inner.doDecode(ctx);
    if (out is DecodeFail<T>) return out;
    final ok = out as DecodeOk<T>;
    final bool passed;
    try {
      passed = _predicate(ok.value);
    } catch (e) {
      return ctx.fail(CustomKind('refine predicate threw: $e'), actual: ok.value, cause: e);
    }
    if (passed) return ok;
    return ctx.fail(FailedRefinement(_message), actual: ok.value);
  }

  @override
  Object? doEncode(T value) => _inner.doEncode(value);
}

final class _BimapCodec<A, B> extends Codec<B> {
  const _BimapCodec(this._inner, this._forward, this._reverse);
  final Codec<A> _inner;
  final B Function(A) _forward;
  final A Function(B) _reverse;

  @override
  DecodeOutcome<B> doDecode(DecodeContext ctx) {
    final out = _inner.doDecode(ctx);
    if (out is DecodeFail<A>) return out.recast<B>();
    final ok = out as DecodeOk<A>;
    try {
      return DecodeOk(_forward(ok.value));
    } catch (e) {
      return ctx.fail(
        CustomKind('bimap forward threw: $e'),
        actual: ok.value,
        cause: e,
      );
    }
  }

  @override
  Object? doEncode(B value) => _inner.doEncode(_reverse(value));
}

final class _ListCodec<T> extends Codec<List<T>> {
  const _ListCodec(this._inner);
  final Codec<T> _inner;

  @override
  DecodeOutcome<List<T>> doDecode(DecodeContext ctx) {
    final v = ctx.value;
    if (v is! List) return ctx.fail(const WrongType('List'));
    final results = <T>[];
    final accumulated = <DecodeError>[];
    for (var i = 0; i < v.length; i++) {
      final child = ctx.index(i, v[i]);
      final out = _inner.doDecode(child);
      switch (out) {
        case DecodeOk(:final value):
          results.add(value);
        case DecodeFail(:final errors):
          accumulated.addAll(errors);
          if (ctx.mode == ErrorMode.failFast) {
            return DecodeFail<List<T>>(accumulated);
          }
      }
    }
    if (accumulated.isNotEmpty) {
      return DecodeFail<List<T>>(accumulated);
    }
    return DecodeOk(List<T>.unmodifiable(results));
  }

  @override
  Object? doEncode(List<T> value) =>
      value.map(_inner.doEncode).toList(growable: false);
}

final class _MapCodec<V> extends Codec<Map<String, V>> {
  const _MapCodec(this._value);
  final Codec<V> _value;

  @override
  DecodeOutcome<Map<String, V>> doDecode(DecodeContext ctx) {
    final v = ctx.value;
    if (v is! Map) return ctx.fail(const WrongType('Map'));
    final out = <String, V>{};
    final accumulated = <DecodeError>[];
    for (final entry in v.entries) {
      final key = '${entry.key}';
      final child = ctx.field(key, entry.value);
      final r = _value.doDecode(child);
      switch (r) {
        case DecodeOk(:final value):
          out[key] = value;
        case DecodeFail(:final errors):
          accumulated.addAll(errors);
          if (ctx.mode == ErrorMode.failFast) {
            return DecodeFail<Map<String, V>>(accumulated);
          }
      }
    }
    if (accumulated.isNotEmpty) {
      return DecodeFail<Map<String, V>>(accumulated);
    }
    return DecodeOk(Map.unmodifiable(out));
  }

  @override
  Object? doEncode(Map<String, V> value) =>
      value.map((k, v) => MapEntry(k, _value.doEncode(v)));
}

final class _LazyCodec<T> extends Codec<T> {
  _LazyCodec(this._build);
  final Codec<T> Function() _build;
  Codec<T>? _cache;
  Codec<T> get _inner => _cache ??= _build();

  @override
  DecodeOutcome<T> doDecode(DecodeContext ctx) => _inner.doDecode(ctx);

  @override
  Object? doEncode(T value) => _inner.doEncode(value);
}

final class _FirstOfCodec<T> extends Codec<T> {
  const _FirstOfCodec(this._candidates, this._encode);
  final List<Codec<T>> _candidates;
  final Object? Function(T)? _encode;

  @override
  DecodeOutcome<T> doDecode(DecodeContext ctx) {
    final all = <DecodeError>[];
    for (final c in _candidates) {
      final out = c.doDecode(ctx);
      if (out is DecodeOk<T>) return out;
      all.addAll((out as DecodeFail<T>).errors);
    }
    return DecodeFail<T>(all);
  }

  @override
  Object? doEncode(T value) {
    final fn = _encode;
    if (fn != null) return fn(value);
    return _candidates.first.doEncode(value);
  }
}

final class _CustomCodec<T> extends Codec<T> {
  const _CustomCodec(this._decode, this._encode);
  final DecodeOutcome<T> Function(DecodeContext) _decode;
  final Object? Function(T) _encode;

  @override
  DecodeOutcome<T> doDecode(DecodeContext ctx) => _decode(ctx);

  @override
  Object? doEncode(T value) => _encode(value);
}

final class _EnumCodec<T extends Enum> extends Codec<T> {
  const _EnumCodec(this._mapping, this._toJson, this._unknownFallback);
  final Map<String, T> _mapping;
  final String Function(T)? _toJson;
  final T? _unknownFallback;

  @override
  DecodeOutcome<T> doDecode(DecodeContext ctx) {
    final v = ctx.value;
    if (v is! String) return ctx.fail(const WrongType('String'));
    final mapped = _mapping[v];
    if (mapped != null) return DecodeOk(mapped);
    // 未知 tag：配了 unknownFallback 则回落，否则维持严格报错暴露 schema 漂移。
    final fallback = _unknownFallback;
    if (fallback != null) return DecodeOk(fallback);
    return ctx.fail(UnknownTag(v, _mapping.keys.toList(growable: false)));
  }

  @override
  Object? doEncode(T value) {
    final fn = _toJson;
    return fn != null ? fn(value) : value.name;
  }
}

final class _EnumOfCodec<T extends Enum, V> extends Codec<T> {
  const _EnumOfCodec(
    this._valueCodec,
    this._mapping,
    this._toJson,
    this._unknownFallback,
  );
  final Codec<V> _valueCodec;
  final Map<V, T> _mapping;
  final V Function(T)? _toJson;
  final T? _unknownFallback;

  @override
  DecodeOutcome<T> doDecode(DecodeContext ctx) {
    final inner = _valueCodec.doDecode(ctx);
    if (inner is DecodeFail<V>) return inner.recast<T>();
    final v = (inner as DecodeOk<V>).value;
    final mapped = _mapping[v];
    if (mapped != null) return DecodeOk(mapped);
    // 值解码成功但 tag 未命中：配了 unknownFallback 则回落，否则严格报错。
    // 注意内层 valueCodec 的类型错误（如该收 int 却给 String）已在上面冒泡，
    // 不会被 fallback 吞掉——只兜底「合法值但未知映射」。
    final fallback = _unknownFallback;
    if (fallback != null) return DecodeOk(fallback);
    return ctx.fail(UnknownTag(
      '$v',
      _mapping.keys.map((k) => '$k').toList(growable: false),
    ));
  }

  @override
  Object? doEncode(T value) {
    final fn = _toJson;
    if (fn != null) return _valueCodec.doEncode(fn(value));
    for (final entry in _mapping.entries) {
      if (entry.value == value) return _valueCodec.doEncode(entry.key);
    }
    throw EncodeException._(
      message: 'enum value $value not present in enumOf mapping',
      hint: '$T',
    );
  }
}
