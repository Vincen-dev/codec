part of '../codec.dart';

// ===========================================================================
// 路径
// ===========================================================================

/// JSON 路径节点，从根 (`$`) 出发的不可变链表。
///
/// 进入子字段/索引时只构造新节点，不复制路径——延迟到 [render] 一次性
/// 字符串化，避免嵌套深时的多次字符串分配。
sealed class PathSegment {
  const PathSegment(this.parent);

  final PathSegment? parent;

  /// 渲染为 JsonPath 风格字符串：`$.user.contacts[2].phone`
  String render() {
    final buf = StringBuffer(r'$');
    _walk(this, buf);
    return buf.toString();
  }

  static void _walk(PathSegment? s, StringBuffer buf) {
    if (s == null) return;
    _walk(s.parent, buf);
    switch (s) {
      case PathField(:final name):
        buf
          ..write('.')
          ..write(name);
      case PathIndex(:final index):
        buf
          ..write('[')
          ..write(index)
          ..write(']');
    }
  }

  @override
  String toString() => render();
}

final class PathField extends PathSegment {
  const PathField(super.parent, this.name);
  final String name;
}

final class PathIndex extends PathSegment {
  const PathIndex(super.parent, this.index);
  final int index;
}

// ===========================================================================
// 错误种类
// ===========================================================================

/// 错误种类：sealed 让监控/i18n 用 pattern match 而非字符串解析。
sealed class DecodeErrorKind {
  const DecodeErrorKind();
  String describe();
  @override
  String toString() => describe();
}

final class MissingField extends DecodeErrorKind {
  const MissingField();
  @override
  String describe() => 'missing required field';
}

final class IsNullField extends DecodeErrorKind {
  const IsNullField();
  @override
  String describe() => 'value is null';
}

final class WrongType extends DecodeErrorKind {
  const WrongType(this.expected);
  final String expected;
  @override
  String describe() => 'expected $expected';
}

final class BadFormat extends DecodeErrorKind {
  const BadFormat(this.detail);
  final String detail;
  @override
  String describe() => 'bad format: $detail';
}

final class FailedRefinement extends DecodeErrorKind {
  const FailedRefinement(this.message);
  final String message;
  @override
  String describe() => 'refinement failed: $message';
}

final class UnknownTag extends DecodeErrorKind {
  const UnknownTag(this.tag, this.allowed);
  final String tag;
  final List<String> allowed;
  @override
  String describe() => 'unknown discriminant tag "$tag" '
      '(allowed: ${allowed.join(', ')})';
}

final class CustomKind extends DecodeErrorKind {
  const CustomKind(this.message);
  final String message;
  @override
  String describe() => message;
}

/// 顶层 decode() 兜底捕获的意外裸异常（通常是 codec 自身 bug，而非数据问题）。
/// 出现时 path 为根（$）——已脱离嵌套上下文。
final class UnexpectedError extends DecodeErrorKind {
  const UnexpectedError(this.error);
  final Object error;
  @override
  String describe() => 'unexpected error: $error';
}

// ===========================================================================
// 错误数据
// ===========================================================================

/// 单个字段级别错误。
///
/// [Codec.decode] 会把一组 [DecodeError] 聚合成一条 [DecodeException]
/// 抛出，message 含全部错误的 path 与原因。
final class DecodeError {
  const DecodeError({
    required this.path,
    required this.kind,
    this.actual,
    this.cause,
  });

  final PathSegment? path;
  final DecodeErrorKind kind;
  final Object? actual;
  final Object? cause;

  String get pathOrRoot => path?.render() ?? r'$';

  @override
  String toString() {
    final got = actual == null
        ? ''
        : ', got: ${_short(actual)} (${actual.runtimeType})';
    final by = cause == null ? '' : '\n  caused by: $cause';
    return '$pathOrRoot: ${kind.describe()}$got$by';
  }

  static String _short(Object? v) {
    final s = '$v';
    return s.length <= 80 ? s : '${s.substring(0, 77)}...';
  }
}

// ===========================================================================
// 错误聚合策略
// ===========================================================================

/// 错误聚合策略。
///
/// 注意：accumulate 仅在 [Codec.list]、[Codec.mapOf]、[Codec.firstOf]
/// 兄弟分支之间生效；object builder 内部永远是 fail-fast 的——这是
/// imperative builder 风格的固有约束，避免一个字段失败后链式调用 NPE。
enum ErrorMode { failFast, accumulate }

// ===========================================================================
// codec 异常体系
//
// [CodecException] 是独立异常层级（`implements Exception`），**不**再继承
// dart SDK 的 [FormatException]。这是默认抛出类型：[Codec.decode] 失败抛
// [DecodeException]，[Codec.encode] 失败抛 [EncodeException]，二者都通过
// [DecodeException] / [EncodeException] 子类暴露**结构化字段**，调用方需要
// 细粒度处理时按类型分支即可：
//
// ```dart
// try { return UserModel.fromJson(json); }
// on DecodeException catch (e) {
//   if (e.isAllMissing) return UserModel.empty();
//   if (e.errors.any((x) => x.kind is BadFormat)) Sentry.report(e);
//   rethrow;
// } on EncodeException catch (e) {
//   assert(false, 'codec encode failed: ${e.message}');
//   rethrow;
// }
// ```
//
// 兼容模式：业务侧统一按 `on FormatException` 兜底的代码，
// 可在组合链最外层套 `.withFormatExceptions()`，使该 codec
// 的 decode/encode 出口改抛 Dart 内置 [FormatException]，无需改动 catch。
// ===========================================================================

/// codec 异常根类。**外部不可直接构造**——抛出由 [Codec.decode] /
/// [Codec.encode] 公开 API 完成。这是一个独立异常层级（`implements
/// Exception`），是默认抛出类型；优先 catch [DecodeException] /
/// [EncodeException] 拿结构化字段。需要与既有 `on FormatException` 处理
/// 逻辑兼容时，对顶层 codec 调用 [Codec.withFormatExceptions]。
sealed class CodecException implements Exception {
  CodecException._(this.message, this.hint);

  /// 已聚合渲染的可读信息。
  final String message;

  /// 操作目标类型名。
  final String hint;

  @override
  String toString() => message;
}

/// decode 失败：JSON 不符合 model 契约，**外部数据**问题。
///
/// 字段：
/// - [errors]：一组结构化错误（永远 non-empty），含路径 / 错误种类 / 原始值
/// - [hint]：解码目标类型名
/// - [message]：人类可读字符串（已聚合 [errors] 渲染）
///
/// 调用方建议按 [DecodeError.kind]（[DecodeErrorKind] sealed 子类）做
/// pattern match 分类处理，**不要 grep [message]**。
final class DecodeException extends CodecException {
  DecodeException._({
    required String message,
    required String hint,
    required this.errors,
  })  : assert(errors.isNotEmpty, 'DecodeException must carry at least one error'),
        super._(message, hint);

  /// 全部解码错误。永远 non-empty。
  final List<DecodeError> errors;

  /// 是否所有错误都是"字段缺失"。
  ///
  /// 常见用法：JSON 完全空 / 后端没返预期对象时降级为兜底实例，
  /// 而不是当成"协议错"上报。
  bool get isAllMissing => errors.every((e) => e.kind is MissingField);

  /// 是否有任何"字段类型不匹配"——通常意味着后端协议演化了，
  /// 应该上报让协议层修复。
  bool get hasWrongType => errors.any((e) => e.kind is WrongType);
}

/// encode 失败：dart 对象自身问题（一般是**代码 bug**）。
///
/// 典型抛点：
/// - `Codec.object` 没传 `encode` 闭包却被调 `encode`
/// - `bimap` 的 reverse 闭包内部抛错
/// - 自定义 codec 的 `doEncode` 实现里抛非 [EncodeException]
///
/// 字段：
/// - [cause]：原始 dart 异常（如 `StateError`），可空
/// - [causeStackTrace]：[cause] 的抛点堆栈
final class EncodeException extends CodecException {
  EncodeException._({
    required String message,
    required String hint,
    this.cause,
    this.causeStackTrace,
  }) : super._(message, hint);

  /// 触发 encode 失败的原始异常。
  final Object? cause;

  /// [cause] 抛出时的堆栈，供日志诊断。
  final StackTrace? causeStackTrace;
}
