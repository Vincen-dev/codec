part of '../codec.dart';

// ===========================================================================
// Codec 抽象 + 顶层工厂
// ===========================================================================

/// Codec 的抽象基类，对外暴露 [decode] / [encode] 公开 API、链式组合子，
/// 以及顶层 namespace 工厂（[Codec.string]、[Codec.object] 等）。
///
/// 子类只需实现 [doDecode] 与 [doEncode] 两个钩子；公开 API 自动转换错误
/// 模型（[DecodeOutcome] → [CodecException]）。兼容模式见
/// [withFormatExceptions]。
abstract class Codec<T> {
  const Codec();

  // ---- 子类钩子 ----

  DecodeOutcome<T> doDecode(DecodeContext ctx);
  Object? doEncode(T value);

  // ---- 异常出口风格 ----

  // 库内：该 codec 出口是否转抛 FormatException。默认 false；_StyledCodec 覆盖为 true。
  bool get _throwsFormat => false;

  /// 让本 codec 的 decode/encode 出口转抛 Dart 内置 [FormatException]（兼容模式），
  /// 供既有 `on FormatException` 处理代码无改动接住。仅影响被调用 decode/encode
  /// 的这个顶层 codec——放在组合链最外层。
  ///
  /// **注意**：调用 [withFormatExceptions] 后不要再链接其他组合子（例如
  /// `.withFormatExceptions().nullable()`），否则后续组合子会成为新的最外层
  /// codec，其 decode/encode 出口将再次抛出 [CodecException] 而非
  /// [FormatException]。[withFormatExceptions] 必须是链式调用的最后一步。
  Codec<T> withFormatExceptions() => _StyledCodec<T>(this);

  Never _surface(CodecException e, StackTrace st) {
    Error.throwWithStackTrace(_throwsFormat ? FormatException(e.message) : e, st);
  }

  // ---- 公开 API ----

  /// 解码并直接返回值；失败时把所有 [DecodeError] 聚合为一条
  /// [DecodeException] 抛出（默认抛出类型，**不**继承 [FormatException]），
  /// message 形如：
  ///
  /// ```
  /// decode UserModel failed (1 error):
  ///   - $.contacts[2].avatar: expected String, got: 1 (int)
  /// ```
  ///
  /// 调用方需要细粒度处理时 catch [DecodeException] 拿 `errors` 字段；需要与
  /// 既有 `on FormatException` 兜底兼容时用 [withFormatExceptions]。
  T decode(
    Object? json, {
    ErrorMode mode = ErrorMode.failFast,
    String? typeHint,
  }) {
    final DecodeOutcome<T> out;
    try {
      out = doDecode(DecodeContext(value: json, path: null, mode: mode));
    } catch (e, st) {
      // 任何 codec（自定义/refine/lazy 构造/object 构造器等）泄漏的裸异常收敛于此。
      _surface(
        DecodeException._(
          message: 'decode ${typeHint ?? '$T'} failed (unexpected error): $e',
          hint: typeHint ?? '$T',
          errors: [
            DecodeError(path: null, kind: UnexpectedError(e), actual: json, cause: e),
          ],
        ),
        st,
      );
    }
    if (out is DecodeOk<T>) return out.value;
    _surface(
      _buildDecodeException((out as DecodeFail<T>).errors, hint: typeHint ?? '$T'),
      StackTrace.current,
    );
  }

  /// 编码为 JSON 兼容值（Map / List / 原语 / null）。
  ///
  /// 内部 [doEncode] 抛出的任何异常（如 bimap reverse 抛错、object 未提供
  /// encode 闭包）都会被包装为 [EncodeException] 抛出，保留原始 [cause] 与
  /// stack trace。已经是 [EncodeException] 的会原样穿透。
  Object? encode(T value) {
    try {
      return doEncode(value);
    } on EncodeException catch (e, st) {
      _surface(e, st);
    } catch (e, st) {
      _surface(
        EncodeException._(
          message: 'encode $T failed: $e',
          hint: '$T',
          cause: e,
          causeStackTrace: st,
        ),
        st,
      );
    }
  }

  // ---- 链式组合子 ----

  /// 接受 null（输出 [Null]），其他走 inner。
  Codec<T?> nullable() => _NullableCodec<T>(this);

  /// 输入为 `null` 时回落到 [fallback]；类型/格式错误**不**回落，仍正常报错。
  ///
  /// 这是有意设计：让协议层 schema 漂移（int 字段突然给字符串）暴露出来，
  /// 而不是被 fallback 静默吞掉。需要"任何失败都兜底"的语义请显式用
  /// [Codec.firstOf] 把回退路径写明。
  Codec<T> withDefault(T fallback) => _DefaultCodec<T>(this, fallback);

  /// 解码成功后再做断言；失败抛 [FailedRefinement]。
  Codec<T> refine(bool Function(T) predicate, String message) =>
      _RefineCodec<T>(this, predicate, message);

  /// 与领域类型双向映射。
  Codec<R> bimap<R>(R Function(T) forward, T Function(R) reverse) =>
      _BimapCodec<T, R>(this, forward, reverse);

  /// 包成 `List<T>`。
  Codec<List<T>> list() => _ListCodec<T>(this);

  /// 兜底：本 codec 失败则尝试 [other]。
  Codec<T> orElse(Codec<T> other) =>
      _FirstOfCodec<T>([this, other], null);

  // ---- 顶层工厂 namespace ----

  static const Codec<String> string = _StringCodec();
  static const Codec<bool> boolean = _BoolCodec();
  static const Codec<int> integer = _IntCodec();
  static const Codec<double> number = _DoubleCodec();
  static const Codec<num> numeric = _NumCodec();
  /// ISO-8601 字符串 / epoch 毫秒；编码输出 ISO-8601（保留原时区）。
  static const Codec<DateTime> dateTime = _DateTimeCodec();

  /// 同 [dateTime]，但 [encode] 时强制 `toUtc()`，避免跨时区下输出歧义。
  static const Codec<DateTime> dateTimeUtc =
      _DateTimeCodec(encodeUtc: true);

  /// epoch **秒**而非毫秒；ISO-8601 字符串仍然可解。后端用 Unix
  /// 秒级时间戳时使用，避免被 [dateTime] 当成毫秒错误解读为 1970 附近。
  static const Codec<DateTime> dateTimeSeconds =
      _DateTimeCodec(epochUnit: DateTimeEpochUnit.seconds);

  /// epoch 毫秒数字 ↔ **UTC** [DateTime] 的双向 codec：decode 仅接受数字，
  /// 输出 `isUtc=true`；encode 回到毫秒整数（不是 ISO 字符串）。
  ///
  /// 适合"后端发毫秒时间戳 + 业务对时区敏感"的场景：相比 [dateTime] 把
  /// 数字 decode 成 isUtc=false 的本地标记，本 codec 让业务侧 `.year` /
  /// `.day` 等访问按 UTC 计算，跨设备一致；相比 [dateTimeUtc] 仅修正
  /// encode 路径，本 codec 双向对称。
  static const Codec<DateTime> dateTimeMillisUtc =
      _DateTimeEpochCodec(unit: DateTimeEpochUnit.milliseconds);

  /// epoch **秒**数字 ↔ UTC [DateTime] 的双向 codec；encode 输出整数秒。
  /// 子秒精度会被秒级协议截断。
  static const Codec<DateTime> dateTimeSecondsUtc =
      _DateTimeEpochCodec(unit: DateTimeEpochUnit.seconds);

  static const Codec<Object?> any = _AnyCodec();

  /// trim 过的字符串。
  static final Codec<String> trimmedString =
      string.bimap((s) => s.trim(), (s) => s);

  /// 非空字符串（trim 后非空）。
  static final Codec<String> nonEmptyString = trimmedString.refine(
    (s) => s.isNotEmpty,
    'must not be empty',
  );

  /// 解码 `Map<String, dynamic>` 为对象。
  ///
  /// [decode] 通过 [FieldsReader] 取字段；[encode] 给出 toJson 实现，
  /// 可空，但调用 [Codec.encode] 时会抛 [EncodeException]。
  static Codec<T> object<T>(
    T Function(FieldsReader) decode, {
    Map<String, Object?> Function(T)? encode,
  }) =>
      _ObjectCodec<T>(decode, encode);

  /// 判别字段联合（discriminated union）。
  ///
  /// [tag] 是判别字段名；[cases] 把每个 tag 值映射到对应分支 codec；
  /// [encode] 把领域值转回 `(tag, body)` 二元组。
  static Codec<T> discriminated<T>({
    required String tag,
    required Map<String, Codec<T>> cases,
    required (String, Map<String, Object?>) Function(T) encode,
  }) =>
      _DiscriminatedCodec<T>(tag, cases, encode);

  /// 递归 codec：用 [build] 工厂延迟构造，自动缓存。
  static Codec<T> lazy<T>(Codec<T> Function() build) =>
      _LazyCodec<T>(build);

  /// 按顺序尝试候选 codec，第一个成功的赢；全部失败则汇总错误。
  static Codec<T> firstOf<T>(
    List<Codec<T>> candidates, {
    Object? Function(T)? encode,
  }) =>
      _FirstOfCodec<T>(candidates, encode);

  /// 完全自定义 codec。
  static Codec<T> custom<T>({
    required DecodeOutcome<T> Function(DecodeContext) decode,
    required Object? Function(T) encode,
  }) =>
      _CustomCodec<T>(decode, encode);

  /// `Map<String, V>` codec。
  static Codec<Map<String, V>> mapOf<V>(Codec<V> value) =>
      _MapCodec<V>(value);

  /// 根据后端 string 值映射到 enum 的 codec。
  ///
  /// [mapping] 给出 `string -> T`；[toJson] 反向映射，可空（默认用
  /// `T.name`）。未知 string 值默认得到 [UnknownTag] 错误并列出合法集；
  /// 若给了 [unknownFallback]，未知值改为回落到该枚举值（不报错）——
  /// 适合后端可能新增枚举项、前端需向前兼容而非整体解码失败的场景。
  static Codec<T> enumByName<T extends Enum>(
    Map<String, T> mapping, {
    String Function(T)? toJson,
    T? unknownFallback,
  }) =>
      _EnumCodec<T>(mapping, toJson, unknownFallback);

  /// 用任意类型 [V] 作为 JSON 值映射 enum；典型场景：int code、自定义 String。
  ///
  /// [valueCodec] 解码 / 编码 JSON 形态的值；[mapping] 给出 `V -> T`；
  /// [toJson] 可空，缺省时反查 [mapping] 取第一个匹配项。未知值默认抛
  /// [UnknownTag] 并列出合法集（值用 `toString()` 渲染）；若给了
  /// [unknownFallback]，未知值改为回落到该枚举值（[valueCodec] 自身的
  /// 类型错误仍照常冒泡，不被兜底吞掉）。
  ///
  /// ```dart
  /// // 后端用 int code，新增地区不致整单解码失败
  /// final c = Codec.enumOf<StoreAreaEnum, int>(
  ///   Codec.integer,
  ///   const {84: StoreAreaEnum.hk, 99: StoreAreaEnum.jp},
  ///   unknownFallback: StoreAreaEnum.hk,
  /// );
  /// ```
  static Codec<T> enumOf<T extends Enum, V>(
    Codec<V> valueCodec,
    Map<V, T> mapping, {
    V Function(T)? toJson,
    T? unknownFallback,
  }) =>
      _EnumOfCodec<T, V>(valueCodec, mapping, toJson, unknownFallback);
}

// ===========================================================================
// 错误聚合 → DecodeException
// ===========================================================================

DecodeException _buildDecodeException(
  List<DecodeError> errors, {
  required String hint,
}) {
  final buf = StringBuffer('decode $hint failed (')
    ..write(errors.length)
    ..write(' error');
  if (errors.length > 1) buf.write('s');
  buf.write('):');
  for (final e in errors) {
    buf
      ..writeln()
      ..write('  - ')
      ..write(e);
  }
  // message 自身已经包含每条错误的 path 与值的诊断信息，是自洽的可读串。
  return DecodeException._(
    message: buf.toString(),
    hint: hint,
    errors: errors,
  );
}

// ===========================================================================
// encode 辅助：null 字段过滤
// ===========================================================================

/// 把 map 里 value 为 `null` 的条目剔除，返回新 map。
///
/// 等价于 json_serializable 的 `@JsonSerializable(includeIfNull: false)`：
/// 序列化时跳过值为 null 的字段，避免请求体出现 `"x": null`。
///
/// codec 的 `encode` 闭包是手写 map 字面量，无法用注解控制；用这个 getter
/// 替代散落的 `if (x != null) 'x': x` 写法，可读性显著提升。
///
/// ```dart
/// // 旧（json_serializable）
/// @JsonSerializable(includeIfNull: false)
/// final class Foo {
///   final String? bar;
///   final int? baz;
/// }
///
/// // 新（codec）
/// encode: (foo) => {
///   'name': foo.name,
///   'bar': foo.bar,
///   'baz': foo.baz,
/// }.omitNulls,
/// ```
///
/// 行为细节：
/// - **不递归**：仅过滤本级 entries，嵌套 map 的 null value 不会被处理；
///   嵌套场景请在嵌套 encode 闭包里再次调用 `.omitNulls`。
/// - **保留 falsy**：`false` / `0` / `''` / 空 list / 空 map 均会保留，
///   只针对严格 `null`，对齐 json_serializable 语义。
/// - **保持插入顺序**：底层 `Map<String, V>` 字面量是 `LinkedHashMap`，
///   返回值按原 key 顺序输出，方便比对请求体快照。
extension MapOmitNulls<V extends Object> on Map<String, V?> {
  Map<String, V> get omitNulls => {
        for (final MapEntry(:key, :value) in entries)
          if (value != null) key: value,
      };
}
