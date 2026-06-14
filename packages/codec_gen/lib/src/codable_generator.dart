import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:build/build.dart';
import 'package:codec/codec.dart';
import 'package:source_gen/source_gen.dart';

import 'codec_resolver.dart';
import 'naming.dart';
import 'runtime_api.dart';

/// 处理 `@Codable` 类。生成顶层 `_$xxxCodec` final 字段。
class CodableGenerator extends GeneratorForAnnotation<Codable> {
  CodableGenerator({
    this.formatExceptions = false,
    this.defaultFieldRename = FieldRename.none,
  });

  /// `true` 时在顶层 codec 表达式末尾追加 `.withFormatExceptions()`，
  /// 使其 decode/encode 抛出 [FormatException] 而非 [CodecException]。
  /// 对应 build.yaml 的 `exception_style: format`。
  final bool formatExceptions;

  /// 项目级默认字段重命名策略（来自 build.yaml `field_rename`）。
  /// `@Codable(fieldRename:)` 未显式给值（注解里为 null）时回落到它。
  final FieldRename defaultFieldRename;

  /// 仅包装顶层 codec 表达式；helper 声明（enumValueField）不受影响。
  String _applyStyle(String codecExpr) =>
      formatExceptions ? '($codecExpr).withFormatExceptions()' : codecExpr;

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@Codable can only be applied to a class (${element.name ?? '<unknown>'})',
        element: element,
      );
    }

    final cls = element;
    final classNameLower = lowerFirst(cls.name!);
    final codecVarName = '_\$${classNameLower}Codec';

    final ctor = cls.unnamedConstructor;
    if (ctor == null) {
      throw InvalidGenerationSourceError(
        '@Codable class ${cls.name!} is missing an unnamed constructor',
        element: cls,
      );
    }

    final classConfig = _readCodableAnnotation(annotation);

    final resolver = CodecResolver(selfClass: cls);

    final decodeLines = <String>[];
    final encodeEntries = <String>[];

    // @CodecField(enumValueField:) 字段产出的顶层 helper codec 声明，拼到
    // 本类 codec 之前。顶层 final 保证整 model 内只构建一次，避免 inline
    // 到每个 encode/decode 用点重建非 const 的映射 map。
    final enumValueFieldHelpers = <String>[];

    // 同一 coreCodec 的 .nullable() wrapper 在整个 model 内共享一份，
    // 避免每次 encode 都新建 _NullableCodec 实例。键为 coreCodec 表达式，
    // 值为分配的局部变量名（_n0 / _n1 ...）。
    final nullableWrappers = <String, String>{};
    String wrapperFor(String coreCodec) => nullableWrappers.putIfAbsent(
          coreCodec,
          () => 'n${nullableWrappers.length}',
        );

    for (final param in ctor.formalParameters) {
      final field = cls.getField(param.name!);
      if (field == null) {
        throw InvalidGenerationSourceError(
          '${cls.name!}.${param.name!} is not a field (constructor parameter must correspond to a field)',
          element: param,
        );
      }

      final fieldConfig = _readFieldAnnotation(field);
      if (fieldConfig.ignore || _hasCodecIgnore(field)) continue;

      // unknownEnumValue 只在 enumValueField 路径生效；脱离 enumValueField 单独
      // 设置（含被 codec: 覆盖的情形）属误用，直接报错而非静默忽略。
      if (fieldConfig.unknownEnumValue != null &&
          fieldConfig.enumValueField == null) {
        throw InvalidGenerationSourceError(
          '${cls.name!}.${param.name!}: @CodecField(unknownEnumValue:) '
          'can only be used together with enumValueField',
          element: field,
        );
      }

      final jsonKey =
          fieldConfig.name ?? renameField(field.name!, classConfig.fieldRename);

      // 字段顶层 codec：non-null 形态；nullable 由 b.optional / .nullable() 控制。
      // 优先级：@CodecField(codec:) > @CodecField(dateTime:) > 类型自动推断
      //
      // 同时拿到 typeArg（codec 的 [T] 字符串），让 b.required<T> / b.optional<T> /
      // b.optionalOr<T> 显式带泛型，生成代码不再依赖 Dart 编译器从构造器参数
      // 反推 T——内置 codec 里 Codec.any (Codec<Object?>) 的 T 自身可空，
      // 反推会得到 non-nullable Object 而类型不匹配；显式泛型一次性解决，且
      // 未来新增任何 T 可空 codec 都不会再撞同款坑。
      //
      // 自定义 codec / dateTime 分支 resolver 不参与，generator 端按约定补全
      // typeArg：dateTime 模式恒为 DateTime；自定义 codec 用字段类型 strip
      // nullable 作 fallback（用户责任：codec T 必须与字段类型一致）。
      final CodecResolution resolved;
      if (fieldConfig.codec != null) {
        resolved = (
          expr: fieldConfig.codec!,
          typeArg: _stripNullableSuffix(field.type.getDisplayString()),
        );
      } else if (fieldConfig.enumValueField != null) {
        // 枚举按字段值映射：产出顶层 helper，coreCodec 引用它（不 inline）。
        final helper = _enumValueFieldCodec(
          cls,
          field,
          fieldConfig.enumValueField!,
          fieldConfig.unknownEnumValue,
        );
        enumValueFieldHelpers.add(helper.decl);
        resolved = (expr: helper.varName, typeArg: helper.typeArg);
      } else if (fieldConfig.dateTime != null) {
        resolved = (
          expr: _dateTimeCodecFor(fieldConfig.dateTime!),
          typeArg: 'DateTime',
        );
      } else {
        resolved = resolver.resolve(field.type, field);
      }
      final coreCodec = resolved.expr;
      final typeArg = resolved.typeArg;

      final isNullable = field.type.nullabilitySuffix == NullabilitySuffix.question;

      // 默认值优先级：@CodecField(defaultValue:) > 构造器参数默认值 > 无默认。
      // 构造器默认值由 source_gen 直接给出字符串形式（如 "''" / "0" / "const []"），
      // 可原样 inline 到生成代码里。`'null'` 视为无默认（b.optional 自然处理）。
      final ctorDefault = param.defaultValueCode;
      final effectiveDefault = fieldConfig.defaultValueLiteral ??
          (ctorDefault == null || ctorDefault == 'null' ? null : ctorDefault);

      final readerCall = _buildReaderCall(
        jsonKey: jsonKey,
        coreCodec: coreCodec,
        typeArg: typeArg,
        isNullable: isNullable,
        defaultValue: effectiveDefault,
        required: fieldConfig.required,
        wrapperFor: wrapperFor,
      );
      decodeLines.add('    ${param.name!}: $readerCall,');

      // 字段级 includeIfNull 优先于类级；non-null 字段不存在 null 输出问题
      final effectiveIncludeIfNull =
          fieldConfig.includeIfNull ?? classConfig.includeIfNull;
      final omitWhenNull = isNullable && !effectiveIncludeIfNull;

      if (omitWhenNull) {
        // dart map literal 的 if 元素：v.x == null 时整条 entry 不出现，
        // guard 后用 ! 解包，让 codec.encode 接收 non-null 形态
        encodeEntries.add(
          "    if (v.${field.name!} != null) "
          "${dartStringLiteral(jsonKey)}: $coreCodec.encode(v.${field.name!}!),",
        );
      } else {
        // 保留 null 输出：可空字段共享 .nullable() wrapper
        final encodeCodec = isNullable ? wrapperFor(coreCodec) : coreCodec;
        encodeEntries.add(
          "    ${dartStringLiteral(jsonKey)}: $encodeCodec.encode(v.${field.name!}),",
        );
      }
    }

    final encodeBody = encodeEntries.join('\n');
    final encodeReturn = '{\n$encodeBody\n  }';

    final coreExpr = 'Codec.object<${cls.name!}>(\n'
        '  (b) => ${cls.name!}(\n'
        '${decodeLines.join('\n')}\n'
        '  ),\n'
        '  encode: (v) => $encodeReturn,\n'
        ')';

    final helperPrefix = enumValueFieldHelpers.isEmpty
        ? ''
        : '${enumValueFieldHelpers.join('\n')}\n';

    if (nullableWrappers.isEmpty) {
      return '${helperPrefix}final Codec<${cls.name!}> $codecVarName = '
          '${_applyStyle(coreExpr)};\n';
    }

    final wrapperDecls = nullableWrappers.entries
        .map((e) => '  final ${e.value} = ${e.key}.nullable();')
        .join('\n');

    final iife = '(() {\n$wrapperDecls\n  return $coreExpr;\n})()';
    return '${helperPrefix}final Codec<${cls.name!}> $codecVarName = '
        '${_applyStyle(iife)};\n';
  }

  _CodableConfig _readCodableAnnotation(ConstantReader r) {
    return _CodableConfig(
      includeIfNull: r.read('includeIfNull').boolValue,
      // 注解未写 fieldRename（可空，默认 null）→ ConstantReader.isNull → 回落到
      // 项目级默认；显式写了任何值（含 none）→ 正常解析、覆盖默认。
      fieldRename: _readEnumValue(
        r.read('fieldRename'),
        FieldRename.values,
        defaultFieldRename,
      ),
    );
  }

  T _readEnumValue<T extends Enum>(
    ConstantReader reader,
    List<T> values,
    T fallback,
  ) {
    if (reader.isNull) return fallback;
    final variable = reader.objectValue.variable;
    if (variable == null) return fallback;
    final varName = variable.name;
    if (varName == null) return fallback;
    return values.firstWhere(
      (e) => e.name == varName,
      orElse: () => fallback,
    );
  }

  _FieldConfig _readFieldAnnotation(FieldElement field) {
    const checker = TypeChecker.typeNamedLiterally('CodecField', inPackage: 'codec');
    final ann = checker.firstAnnotationOfExact(field);
    if (ann == null) return const _FieldConfig();

    final r = ConstantReader(ann);
    return _FieldConfig(
      name: r.read('name').isNull ? null : r.read('name').stringValue,
      defaultValueLiteral: _readDefaultValueLiteral(r.read('defaultValue')),
      required: r.read('required').boolValue,
      ignore: r.read('ignore').boolValue,
      codec: r.read('codec').isNull ? null : r.read('codec').stringValue,
      includeIfNull: r.read('includeIfNull').isNull
          ? null
          : r.read('includeIfNull').boolValue,
      dateTime: r.read('dateTime').isNull
          ? null
          : _readEnumValue(
              r.read('dateTime'),
              DateTimeMode.values,
              DateTimeMode.local,
            ),
      enumValueField: r.read('enumValueField').isNull
          ? null
          : r.read('enumValueField').stringValue,
      unknownEnumValue: _readEnumConstant(r.read('unknownEnumValue')),
    );
  }

  /// 读取 `@CodecField(unknownEnumValue:)` 这类「用户自定义枚举常量」注解值，
  /// 拆出 `(枚举类型名, 枚举常量名)`。非枚举常量 / 为 null → null。
  ({String typeName, String constName})? _readEnumConstant(ConstantReader r) {
    if (r.isNull) return null;
    final obj = r.objectValue;
    final variable = obj.variable;
    final typeName = obj.type?.getDisplayString();
    final constName = variable?.name;
    if (constName == null || typeName == null) return null;
    return (typeName: typeName, constName: constName);
  }

  /// 把 `@CodecField(defaultValue: ...)` 的常量字面量转成可 inline 的 dart
  /// 表达式字符串。支持 String / bool / int / double 与 const List / const Map
  /// （含嵌套）；嵌套元素递归同样规则解析，元素类型不支持时显式抛错。
  String? _readDefaultValueLiteral(ConstantReader r) {
    if (r.isNull) return null;
    if (r.isString) return dartStringLiteral(r.stringValue);
    if (r.isBool) return '${r.boolValue}';
    if (r.isInt) return '${r.intValue}';
    if (r.isDouble) return '${r.doubleValue}';
    if (r.isList) {
      final items = r.listValue.map((e) {
        final lit = _readDefaultValueLiteral(ConstantReader(e));
        if (lit == null) {
          throw InvalidGenerationSourceError(
            '@CodecField(defaultValue: [...]) contains an unsupported element type',
          );
        }
        return lit;
      }).join(', ');
      return 'const [$items]';
    }
    if (r.isMap) {
      final entries = r.mapValue.entries.map((e) {
        final keyLit = e.key == null
            ? null
            : _readDefaultValueLiteral(ConstantReader(e.key!));
        final valLit = e.value == null
            ? null
            : _readDefaultValueLiteral(ConstantReader(e.value!));
        if (keyLit == null || valLit == null) {
          throw InvalidGenerationSourceError(
            '@CodecField(defaultValue: {...}) contains an unsupported key or value type',
          );
        }
        return '$keyLit: $valLit';
      }).join(', ');
      return 'const {$entries}';
    }
    throw InvalidGenerationSourceError(
      '@CodecField(defaultValue: ...) only supports String / bool / int / double / '
      'const List / const Map literals',
    );
  }

  bool _hasCodecIgnore(FieldElement field) {
    const checker = TypeChecker.typeNamedLiterally('CodecIgnore', inPackage: 'codec');
    return checker.hasAnnotationOfExact(field);
  }

  String _dateTimeCodecFor(DateTimeMode mode) => switch (mode) {
        DateTimeMode.local => RuntimeApi.dateTime,
        DateTimeMode.utc => RuntimeApi.dateTimeUtc,
        DateTimeMode.seconds => RuntimeApi.dateTimeSeconds,
        DateTimeMode.millisUtc => RuntimeApi.dateTimeMillisUtc,
        DateTimeMode.secondsUtc => RuntimeApi.dateTimeSecondsUtc,
      };

  /// 为 `@CodecField(enumValueField:)` 字段生成顶层 helper codec。
  ///
  /// 返回 helper 变量名、枚举类型名、helper 顶层声明源码。helper 命名用
  /// 类名 + 字段名而非枚举 + valueField：同文件多个 `@Codable` 类各自独立
  /// 生成，按枚举命名会撞顶层名，按类 + 字段命名保证唯一。
  ({String varName, String typeArg, String decl}) _enumValueFieldCodec(
    ClassElement cls,
    FieldElement field,
    String valueField,
    ({String typeName, String constName})? unknownEnumValue,
  ) {
    final element = field.type.element;
    if (element is! EnumElement) {
      throw InvalidGenerationSourceError(
        '@CodecField(enumValueField: ...) can only be used on an enum field '
        '(${cls.name!}.${field.name!} has type ${field.type.getDisplayString()})',
        element: field,
      );
    }
    final enumName = element.name!;

    // unknownEnumValue 的枚举类型须与字段枚举一致，否则生成代码会编译失败，
    // 这里提前给出清晰报错。
    if (unknownEnumValue != null && unknownEnumValue.typeName != enumName) {
      throw InvalidGenerationSourceError(
        '${cls.name!}.${field.name!}: @CodecField(unknownEnumValue:) type '
        '${unknownEnumValue.typeName} does not match field enum $enumName',
        element: field,
      );
    }
    final vField = element.getField(valueField);
    if (vField == null) {
      throw InvalidGenerationSourceError(
        "@CodecField(enumValueField: '$valueField') field '$valueField' not found on $enumName",
        element: field,
      );
    }
    final fieldTypeStr = vField.type.getDisplayString();
    final innerCodec = switch (fieldTypeStr) {
      'int' => 'Codec.integer',
      'String' => 'Codec.string',
      'double' => 'Codec.number',
      'num' => 'Codec.numeric',
      _ => throw InvalidGenerationSourceError(
          'enumValueField $valueField has unsupported type $fieldTypeStr '
          '(only int / String / double / num are supported)',
          element: field,
        ),
    };

    final varName =
        '_\$${lowerFirst(cls.name!)}${upperFirst(field.name!)}EnumCodec';
    // Map 不带 const：枚举实例字段访问在 const 表达式里受限。
    final mapEntries = element.fields
        .where((f) => f.isEnumConstant)
        .map((v) => '  $enumName.${v.name!}.$valueField: $enumName.${v.name!},')
        .join('\n');
    final fallbackArg = unknownEnumValue == null
        ? ''
        : '  unknownFallback: $enumName.${unknownEnumValue.constName},\n';
    final decl = '''
// $enumName.$valueField 字段级映射（${cls.name!}.${field.name!} 专用）。
final Codec<$enumName> $varName = Codec.enumOf<$enumName, $fieldTypeStr>(
  $innerCodec,
  {
$mapEntries
  },
$fallbackArg);
''';
    return (varName: varName, typeArg: enumName, decl: decl);
  }

  String _buildReaderCall({
    required String jsonKey,
    required String coreCodec,
    required String typeArg,
    required bool isNullable,
    required String? defaultValue,
    required bool required,
    required String Function(String coreCodec) wrapperFor,
  }) {
    // required + nullable / optionalOr + nullable 走 b.required<T?>(...,
    // codec.nullable()) 形态。若 typeArg 自身已可空（Codec.any 的 Object?），
    // 不重复追加 ?，避免生成 `Object??` 这种合法但难读的形态。
    String nullify(String t) => t.endsWith('?') ? t : '$t?';

    // required + nullable：必须出现 key，值可 null → inner 用共享 nullable wrapper
    if (required) {
      final t = isNullable ? nullify(typeArg) : typeArg;
      final inner = isNullable ? wrapperFor(coreCodec) : coreCodec;
      return "b.required<$t>(${dartStringLiteral(jsonKey)}, $inner)";
    }
    if (defaultValue != null) {
      // optionalOr 的 default 类型匹配字段类型；nullable 字段配 default 一般少见
      final t = isNullable ? nullify(typeArg) : typeArg;
      final inner = isNullable ? wrapperFor(coreCodec) : coreCodec;
      return "b.optionalOr<$t>(${dartStringLiteral(jsonKey)}, $inner, $defaultValue)";
    }
    if (isNullable) {
      // b.optional<T>(...) 自身返回 T?；T 用 codec 的 typeArg（不追加 ?）
      // ——对 Codec.any 也保持 Object?，让返回值是 Object??（Dart 折叠为 Object?）
      return "b.optional<$typeArg>(${dartStringLiteral(jsonKey)}, $coreCodec)";
    }
    // non-null 字段、无 default、无 required → 等价于必填
    return "b.required<$typeArg>(${dartStringLiteral(jsonKey)}, $coreCodec)";
  }

  /// 把类型字符串末尾的 `?` 剥掉。仅给自定义 codec（[CodecField.codec]）路径
  /// 用来推断 typeArg——resolver 路径自带 typeArg、不走此函数。
  static String _stripNullableSuffix(String typeStr) =>
      typeStr.endsWith('?') ? typeStr.substring(0, typeStr.length - 1) : typeStr;
}

class _CodableConfig {
  const _CodableConfig({required this.includeIfNull, required this.fieldRename});
  final bool includeIfNull;
  final FieldRename fieldRename;
}

class _FieldConfig {
  const _FieldConfig({
    this.name,
    this.defaultValueLiteral,
    this.required = false,
    this.ignore = false,
    this.codec,
    this.includeIfNull,
    this.dateTime,
    this.enumValueField,
    this.unknownEnumValue,
  });
  final String? name;
  final String? defaultValueLiteral;
  final bool required;
  final bool ignore;
  final String? codec;
  final bool? includeIfNull;
  final DateTimeMode? dateTime;
  final String? enumValueField;

  /// `@CodecField(unknownEnumValue:)` 解析出的 `(枚举类型名, 枚举常量名)`，
  /// 用于生成 `Codec.enumOf(..., unknownFallback: 类型.常量)`；未配则为 null。
  final ({String typeName, String constName})? unknownEnumValue;
}
