import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';

/// codec 表达式 + 该 codec 的 [T] 类型字符串。
///
/// generator 拼装读取调用时需要显式 `b.required<T>` / `b.optional<T>` 等
/// 泛型注入——仅依赖 Dart 编译器从构造器参数反推 `T`，会在 codec 的 `T`
/// 自身就含 nullable 信息（如 `Codec.any: Codec<Object?>`）时反推成
/// non-nullable 形态、与传入 codec 类型不匹配。把每个字段映射结果同时
/// 携带 expr 与 typeArg，generator 端直接注入显式泛型，生成代码不再依赖
/// 推断，未来新增任何 [T] 可空 codec 也不会再撞同款坑。
typedef CodecResolution = ({String expr, String typeArg});

/// 把 Dart 字段类型映射成 codec 表达式与对应 codec 的 [T] 类型字符串。
///
/// 入口 [resolve] 会自动加 `.nullable()` 包装可空类型（仅 [wrapNullable]
/// 为 true 的嵌套调用使用）；类型分发逻辑在 [_resolveCore]。`selfClass`
/// 用于检测自引用（生成 `Codec.lazy(...)`）。
class CodecResolver {
  CodecResolver({required this.selfClass});

  /// 当前正在处理的 `@Codable` 类，用于检测自引用。
  final ClassElement selfClass;

  static const _codableChecker =
      TypeChecker.typeNamedLiterally('Codable', inPackage: 'codec');
  static const _codecEnumChecker =
      TypeChecker.typeNamedLiterally('CodecEnum', inPackage: 'codec');

  /// 给一个字段类型生成对应 codec 的 (expr, typeArg)。
  ///
  /// [wrapNullable]：是否把可空类型包成 `.nullable()`。**字段顶层**调用时
  /// 应传 false——nullable 处理由调用方（`b.optional` 或 encode 侧的
  /// `.nullable()`）显式管理；**嵌套类型**（List 元素、Map value）调用时
  /// 应传 true，否则 `List<int?>` 会丢可空信息。
  CodecResolution resolve(
    DartType type,
    FieldElement field, {
    bool wrapNullable = false,
  }) {
    final core = _resolveCore(type, field);
    if (wrapNullable &&
        type.nullabilitySuffix == NullabilitySuffix.question) {
      // 给嵌套 codec 加 .nullable() 时，typeArg 同步加 ?——但若 codec 的 T
      // 已经是可空形态（Codec.any 的 Object?），不重复加。
      final wrappedTypeArg =
          core.typeArg.endsWith('?') ? core.typeArg : '${core.typeArg}?';
      return (expr: '${core.expr}.nullable()', typeArg: wrappedTypeArg);
    }
    return core;
  }

  CodecResolution _resolveCore(DartType type, FieldElement field) {
    // 原语
    if (type.isDartCoreString) {
      return (expr: 'Codec.string', typeArg: 'String');
    }
    if (type.isDartCoreInt) {
      return (expr: 'Codec.integer', typeArg: 'int');
    }
    if (type.isDartCoreDouble) {
      return (expr: 'Codec.number', typeArg: 'double');
    }
    if (type.isDartCoreNum) {
      return (expr: 'Codec.numeric', typeArg: 'num');
    }
    if (type.isDartCoreBool) {
      return (expr: 'Codec.boolean', typeArg: 'bool');
    }

    final displayName = type.getDisplayString().replaceAll('?', '');
    if (displayName == 'DateTime') {
      return (expr: 'Codec.dateTime', typeArg: 'DateTime');
    }
    if (displayName == 'Object' || displayName == 'dynamic') {
      // Codec.any 是 Codec<Object?>——内置 codec 里唯一 T 自身可空的，
      // typeArg 必须是 Object? 才能与 codec 类型严格匹配。
      return (expr: 'Codec.any', typeArg: 'Object?');
    }

    // List<T>：嵌套类型走 resolve(wrapNullable: true) 保持元素可空信息
    if (type.isDartCoreList && type is ParameterizedType) {
      final inner = type.typeArguments.first;
      final innerR = resolve(inner, field, wrapNullable: true);
      return (
        expr: '${innerR.expr}.list()',
        typeArg: 'List<${innerR.typeArg}>',
      );
    }

    // Map<String, V>
    if (type.isDartCoreMap && type is ParameterizedType) {
      final args = type.typeArguments;
      if (!args[0].isDartCoreString) {
        throw InvalidGenerationSourceError(
          'Map key must be String (${_owner(field)}.${field.name})',
          element: field,
        );
      }
      final innerR = resolve(args[1], field, wrapNullable: true);
      return (
        expr: 'Codec.mapOf(${innerR.expr})',
        typeArg: 'Map<String, ${innerR.typeArg}>',
      );
    }

    final element = type.element;

    // Enum
    if (element is EnumElement) {
      if (_codecEnumChecker.hasAnnotationOfExact(element)) {
        return (expr: '${element.name!}.codec', typeArg: element.name!);
      }
      // 没挂 @CodecEnum：inline 一段按 .name 的 enumByName，自带追溯注释
      final values = element.fields.where((f) => f.isEnumConstant);
      final entries = values
          .map((v) => "'${v.name!}': ${element.name!}.${v.name!}")
          .join(', ');
      // 注：单行表达式形式，注释由调用方决定要不要追加
      return (
        expr: 'Codec.enumByName(const {$entries})',
        typeArg: element.name!,
      );
    }

    // 嵌套 model
    if (element is ClassElement) {
      // 自引用 → lazy 打破构造循环
      if (element == selfClass) {
        return (
          expr: 'Codec.lazy(() => ${element.name!}.codec)',
          typeArg: element.name!,
        );
      }
      if (!_codableChecker.hasAnnotationOfExact(element)) {
        throw InvalidGenerationSourceError(
          '${_owner(field)}.${field.name} has type ${element.name!} which is not annotated with @Codable, '
          'cannot generate a codec. Either (1) add @Codable() to ${element.name!}, '
          "or (2) specify a field-level codec via @CodecField(codec: 'xxx').",
          element: field,
        );
      }
      return (expr: '${element.name!}.codec', typeArg: element.name!);
    }

    throw InvalidGenerationSourceError(
      '${_owner(field)}.${field.name} has unsupported type ${type.getDisplayString()} '
      "for codec_gen. Use @CodecField(codec: 'xxx') to specify a field-level codec.",
      element: field,
    );
  }

  String _owner(FieldElement field) =>
      field.enclosingElement.displayName;
}
