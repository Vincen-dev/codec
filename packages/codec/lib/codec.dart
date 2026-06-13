/// 类型安全、可组合的 JSON Codec 抽象。
///
/// ## 设计目标
///
/// 1. **失败抛 [CodecException]**：[Codec.decode] / [Codec.encode]
///    直接返回值，失败时抛本库独立的 [CodecException]（[DecodeException] /
///    [EncodeException]），message 携带 [PathSegment] 渲染的路径与
///    [DecodeErrorKind] 描述。内部仍用 [DecodeOutcome] 值化错误便于聚合，
///    仅在出口转异常。需与既有 `on FormatException` 兜底兼容时，对顶层
///    codec 调用 [Codec.withFormatExceptions]。
/// 2. **Codec 是一等对象**：`Codec.string`、`Codec.object(...)` 等返回
///    可传递、可组合的 [Codec]；`.list()` / `.nullable()` / `.refine()` /
///    `.bimap()` 等链式组合子覆盖常见变形。
/// 3. **路径自动追踪**：嵌套字段 / list 元素 / discriminated 分支错误
///    自动带上 `$.user.contacts[2].phone` 形态路径。
/// 4. **复杂场景一等支持**：sealed 联合用 [Codec.discriminated]；递归
///    结构用 [Codec.lazy]；多版本字段兼容用 [Codec.firstOf]。
/// 5. **零第三方依赖**：仅用 Dart SDK。
///
/// ## 包结构
///
/// 包内实现拆分为多个 part 文件，按职责归置；`_xxx` 私有类型仅在
/// library 内可见，外部只能通过 [Codec] 静态工厂与公开类型访问：
///
/// - `src/decode_error.dart` — 路径 / 错误模型 / 错误聚合策略
/// - `src/decode_context.dart` — 解码上下文 / 解码结果代数
/// - `src/codec_base.dart` — Codec 抽象 + 公开 API + 静态工厂 namespace
/// - `src/primitives.dart` — 7 个原语 codec（const 单例）
/// - `src/combinators.dart` — 9 个组合子 codec
/// - `src/object_codec.dart` — Object/Discriminated + FieldsReader DSL
///
/// ## 速览
///
/// ```dart
/// final class UserModel {
///   final String name;
///   final String? avatar;
///   final int age;
///   const UserModel({required this.name, this.avatar, required this.age});
///
///   static final Codec<UserModel> codec = Codec.object<UserModel>(
///     (b) => UserModel(
///       name: b.required('name', Codec.string),
///       avatar: b.optional('avatar', Codec.string),
///       age: b.optionalOr('age', Codec.integer, 0),
///     ),
///     encode: (u) => {
///       'name': u.name,
///       'avatar': u.avatar,
///       'age': u.age,
///     }.omitNulls,
///   );
///
///   factory UserModel.fromJson(Object? json) =>
///       codec.decode(json, typeHint: 'UserModel');
///
///   Object? toJson() => codec.encode(this);
/// }
/// ```
library;

part 'src/decode_error.dart';
part 'src/decode_context.dart';
part 'src/codec_base.dart';
part 'src/primitives.dart';
part 'src/combinators.dart';
part 'src/object_codec.dart';
part 'src/annotations.dart';
