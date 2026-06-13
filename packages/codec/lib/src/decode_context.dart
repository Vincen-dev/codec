part of '../codec.dart';

// ===========================================================================
// 解码上下文
// ===========================================================================

/// 解码运行时上下文：当前值 + 路径栈 + 错误聚合策略。
///
/// 进入子字段/索引时通过 [field]/[index] 派生新上下文，路径自动 push；
/// 失败用 [fail] 构造 [DecodeFail]，错误自动绑定当前 path。
final class DecodeContext {
  const DecodeContext({
    required this.value,
    required this.path,
    required this.mode,
  });

  final Object? value;
  final PathSegment? path;
  final ErrorMode mode;

  DecodeContext field(String name, Object? v) =>
      DecodeContext(value: v, path: PathField(path, name), mode: mode);

  DecodeContext index(int i, Object? v) =>
      DecodeContext(value: v, path: PathIndex(path, i), mode: mode);

  DecodeFail<T> fail<T>(
    DecodeErrorKind kind, {
    Object? actual,
    Object? cause,
  }) =>
      DecodeFail<T>([
        DecodeError(
          path: path,
          kind: kind,
          actual: actual ?? value,
          cause: cause,
        ),
      ]);
}

// ===========================================================================
// 解码结果
// ===========================================================================

/// 解码内部结果——sealed 代数，由 [Codec.decode] 出口转 [CodecException]。
sealed class DecodeOutcome<T> {
  const DecodeOutcome();
  bool get isOk => this is DecodeOk<T>;
}

final class DecodeOk<T> extends DecodeOutcome<T> {
  const DecodeOk(this.value);
  final T value;
}

final class DecodeFail<T> extends DecodeOutcome<T> {
  const DecodeFail(this.errors);
  final List<DecodeError> errors;

  DecodeFail<R> recast<R>() => DecodeFail<R>(errors);
}
