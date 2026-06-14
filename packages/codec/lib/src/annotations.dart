part of '../codec.dart';

// ===========================================================================
// codec_gen 注解（仅 metadata；运行时不读取这些类的实例）
//
// 这些注解类不参与 codec runtime 行为；仅作为 codec_gen 通过 source_gen 静
// 态分析用户代码时识别的标记。把它们与 Codec runtime 同 library 暴露，是
// 为了让用户在 model 文件里只写一次 `import 'package:codec/codec.dart';`
// 就同时拿到 `Codec<T>` API 和 codegen 注解。
// ===========================================================================

/// 标记一个类由 codec_gen 处理；触发生成 `_$xxxCodec` 顶层 const 字段。
///
/// 用户在类内挂 `static final Codec<X> codec = _$xxxCodec;` 暴露给业务调
/// 用方。typical 用法：
///
/// ```dart
/// import 'package:codec/codec.dart';
/// part 'order_model.g.dart';
///
/// @Codable()
/// final class OrderModel {
///   final int orderId;
///   @CodecField(name: 'total_amount', defaultValue: 0.0)
///   final double totalAmount;
///   const OrderModel({required this.orderId, required this.totalAmount});
///
///   static final Codec<OrderModel> codec = _$orderModelCodec;
///   factory OrderModel.fromJson(Object? json) => codec.decode(json);
///   Object? toJson() => codec.encode(this);
/// }
/// ```
final class Codable {
  /// const 构造（注解必须 const）。
  const Codable({
    this.includeIfNull = true,
    this.fieldRename,
  });

  /// 类级默认：toJson 是否输出 null 字段。`false` 时生成代码尾部追加
  /// `.omitNulls`。字段级 [CodecField.includeIfNull] 优先级更高。
  final bool includeIfNull;

  /// 字段名转换策略：dart 字段 → JSON 字段。
  ///
  /// `null`（默认）：继承项目级默认——build.yaml 的 `field_rename`，未配置则
  /// [FieldRename.none]。显式给值（含 [FieldRename.none]）覆盖项目级默认。
  /// 字段级 [CodecField.name] 始终优先于本策略。
  final FieldRename? fieldRename;
}

/// 字段名重命名策略。
enum FieldRename {
  /// 原样使用 dart 字段名。
  none,

  /// `userName` → `user_name`
  snake,

  /// `userName` → `user-name`
  kebab,

  /// `userName` → `UserName`
  pascal,

  /// `userName` → `userName`（与 none 同义；保留以便未来对齐其他工具）
  camel,

  /// `userName` → `USER_NAME`（全大写下划线，常见于 Java/Spring 后端枚举值）
  screamingSnake,
}

/// `@CodecField(...)` 中 `dateTime` 字段的取值。
///
/// 用于在不写 `@CodecField(codec: 'Codec.dateTimeUtc')` 字符串的前提下
/// 切换 `DateTime` 字段的 codec：
///
/// ```dart
/// @CodecField(dateTime: DateTimeMode.utc)      // 强制 toUtc() 编码
/// final DateTime createdAt;
///
/// @CodecField(dateTime: DateTimeMode.seconds)  // epoch 按秒解读
/// final DateTime serverTime;
/// ```
enum DateTimeMode {
  /// `Codec.dateTime`：encode 保留原时区，输出 ISO-8601 字符串。
  local,

  /// `Codec.dateTimeUtc`：encode 强制 `toUtc()`，输出 ISO-8601 字符串。
  utc,

  /// `Codec.dateTimeSeconds`：decode epoch 数字按 Unix 秒解读，encode
  /// 仍输出 ISO-8601 字符串（不对称）。
  seconds,

  /// `Codec.dateTimeMillisUtc`：epoch **毫秒**数字 ↔ UTC `DateTime` 双向，
  /// decode 出 `isUtc=true`、encode 回毫秒整数。后端协议双向都用毫秒
  /// 时间戳且业务对时区敏感时使用。
  millisUtc,

  /// `Codec.dateTimeSecondsUtc`：epoch **秒**数字 ↔ UTC `DateTime` 双向，
  /// encode 输出整数秒（子秒精度被截断）。
  secondsUtc,
}

/// 字段级配置。所有参数可空——只在需要覆盖默认行为时设置。
final class CodecField {
  const CodecField({
    this.name,
    this.defaultValue,
    this.required = false,
    this.ignore = false,
    this.codec,
    this.includeIfNull,
    this.dateTime,
    this.enumValueField,
    this.unknownEnumValue,
  });

  /// JSON 字段名（覆盖类级 [Codable.fieldRename]）。
  final String? name;

  /// 字段缺失或为 null 时回落到该默认值；设了之后字段对外是 non-null。
  ///
  /// 支持的字面量类型：String / bool / int / double / `const List` / `const Map`
  /// （含嵌套）。复杂表达式（构造器调用、运算）请改用构造器参数默认值。
  final Object? defaultValue;

  /// 必填字段：JSON 缺失会抛 [MissingField]，与字段是否可空无关。
  final bool required;

  /// 忽略此字段：codec_gen 不读 / 不写它。typical 用例：transient 字段、
  /// 服务端拒绝接收的本地状态字段。
  ///
  /// 等价于 [CodecIgnore] 注解；二选一即可。
  final bool ignore;

  /// 自定义 codec 引用（同文件内的 const 字段名或导入符号名）。
  ///
  /// 用于 codec_gen 默认不支持的字段类型（discriminated / firstOf 等），
  /// 或字段需要特殊编解码逻辑。生成代码会直接引用这个名字：
  ///
  /// ```dart
  /// @CodecField(codec: '_amountCodec')
  /// final String amount;
  /// // 用户在文件内定义：const _amountCodec = ...;
  /// ```
  final String? codec;

  /// 字段级覆盖：是否输出 null。覆盖类级 [Codable.includeIfNull]。
  ///
  /// `false` 时该字段值为 `null` 会从 toJson 输出中省略；`true` 时无论
  /// 类级如何，该字段始终输出（含 `null`）；`null`（默认）跟随类级设置。
  final bool? includeIfNull;

  /// `DateTime` 字段的 codec 选择，避免写 `codec: 'Codec.dateTimeUtc'` 字符串。
  /// 与 [codec] 互斥（同时设置时 [codec] 优先）。
  final DateTimeMode? dateTime;

  /// 枚举字段按枚举实例的某个字段值（如 `code`）做 JSON 映射，而枚举本身无需
  /// 挂 [CodecEnum]。适合 core / domain 层枚举不想耦合序列化框架的场景。
  ///
  /// ```dart
  /// @CodecField(enumValueField: 'code')  // 枚举保持纯净，无需 @CodecEnum
  /// final OrderState orderState;         // JSON {"orderState": 3} ↔ code 为 3 的值
  /// ```
  ///
  /// 仅用于 enum 字段；目标字段类型须为 int / String / double / num。
  /// 与 [dateTime] 互斥；与 [codec] 同时设置时 [codec] 优先。
  final String? enumValueField;

  /// 仅配合 [enumValueField]：解码遇到未知 code（[enumValueField] 映射未命中）
  /// 时回落到该枚举值，而非抛 UnknownTag 致整条记录解码失败。`null`（默认）
  /// 保持严格——未知 code 仍报错，让协议 schema 漂移暴露而非被静默吞掉。
  ///
  /// 适合后端可能新增 / 调整枚举 code、前端需向前兼容的字段：
  ///
  /// ```dart
  /// @CodecField(enumValueField: 'code', unknownEnumValue: StoreAreaEnum.HK)
  /// final StoreAreaEnum regionId;  // 未知 / 0 → HK，不再整单解码失败
  /// ```
  ///
  /// 枚举类型须与字段一致；不与 [enumValueField] 搭配使用时由 codec_gen 报错。
  final Enum? unknownEnumValue;
}

/// 简写：让 codec_gen 完全跳过此字段。等价于 `@CodecField(ignore: true)`，
/// 但更短、更醒目，适合零 metadata 的纯标记场景。
final class CodecIgnore {
  const CodecIgnore();
}

/// 标记一个 enum 由 codec_gen 处理；触发生成 `_$xxxCodec` 顶层 const 字段。
///
/// **不挂此注解时**：codec_gen 在 `@Codable` 类引用此 enum 处自动 inline
/// 一段按 `.name` 的 `Codec.enumByName(...)`，零样板。需要自定义映射或多
/// 个 model 共享时挂此注解。
final class CodecEnum {
  const CodecEnum({this.valueField});

  /// 用 enum 实例的字段值作为 JSON value。
  ///
  /// ```dart
  /// @CodecEnum(valueField: 'code')
  /// enum Currency {
  ///   HKD(840), JPY(392);
  ///   const Currency(this.code);
  ///   final int code;
  /// }
  /// // JSON {"currency": 840} ↔ Currency.HKD
  /// ```
  ///
  /// 字段级 [CodecValue] 优先级更高（按值单独覆盖）。
  final String? valueField;
}

/// 单个 enum 值的 JSON 映射。覆盖默认 `.name` 与类级 [CodecEnum.valueField]。
///
/// ```dart
/// @CodecEnum()
/// enum Color {
///   @CodecValue('R') red,
///   @CodecValue('G') green,
///   @CodecValue('B') blue,
/// }
/// ```
///
/// [value] 通常是 [String] 或 [int]；同一 enum 内必须类型一致，
/// codec_gen 编译期校验。
///
/// **同一 enum 内的所有值必须全部挂 [CodecValue]，或全部不挂**——部分挂会
/// 让生成的 mapping 漏值，运行时 encode 漏值会抛 `EncodeException`。
/// codec_gen 在 codegen 阶段拒绝这种半挂状态并列出未挂注解的值。
/// 全部不挂时退回到默认 `.name` 或类级 [CodecEnum.valueField] 路径。
final class CodecValue {
  const CodecValue(this.value);

  /// JSON 值。
  final Object value;
}
