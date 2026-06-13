import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:codec/codec.dart';
import 'package:source_gen/source_gen.dart';

import 'codec_enum_validation.dart';
import 'naming.dart';

/// 处理 `@CodecEnum` enum，生成顶层 `_$xxxCodec` const 字段。
class CodecEnumGenerator extends GeneratorForAnnotation<CodecEnum> {
  CodecEnumGenerator({this.formatExceptions = false});

  /// `true` 时在顶层 codec 表达式末尾追加 `.withFormatExceptions()`，
  /// 使其 decode/encode 抛出 [FormatException] 而非 [CodecException]。
  /// 对应 build.yaml 的 `exception_style: format`。
  final bool formatExceptions;

  /// 仅包装顶层 codec 表达式。
  String _applyStyle(String codecExpr) =>
      formatExceptions ? '($codecExpr).withFormatExceptions()' : codecExpr;

  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! EnumElement) {
      throw InvalidGenerationSourceError(
        '@CodecEnum can only be applied to an enum (${element.name ?? '<unknown>'})',
        element: element,
      );
    }

    final enumEl = element;
    final enumName = enumEl.name!;
    final codecVarName = '_\$${lowerFirst(enumName)}Codec';

    final values = enumEl.fields.where((f) => f.isEnumConstant).toList();
    if (values.isEmpty) {
      throw InvalidGenerationSourceError(
        '@CodecEnum $enumName has no enum values',
        element: enumEl,
      );
    }

    // 字段级 @CodecValue 优先；否则看类级 valueField；否则按 .name。
    final valueField = annotation.read('valueField').isNull
        ? null
        : annotation.read('valueField').stringValue;

    const codecValueChecker =
        TypeChecker.typeNamedLiterally('CodecValue', inPackage: 'codec');
    final entries = <_EnumEntry>[];
    final annotatedNames = <String>{};
    bool sawCodecValue = false;
    bool? isStringValue;

    for (final v in values) {
      final ann = codecValueChecker.firstAnnotationOfExact(v);
      if (ann != null) {
        sawCodecValue = true;
        annotatedNames.add(v.name!);
        final reader = ConstantReader(ann).read('value');
        if (reader.isString) {
          if (isStringValue == false) {
            throw InvalidGenerationSourceError(
              '@CodecValue on $enumName.${v.name!}: cannot mix String and int values in the same enum',
              element: v,
            );
          }
          isStringValue = true;
          entries.add(_EnumEntry(
            v.name!,
            dartStringLiteral(reader.stringValue),
            isString: true,
          ));
        } else if (reader.isInt) {
          if (isStringValue == true) {
            throw InvalidGenerationSourceError(
              '@CodecValue on $enumName.${v.name!}: cannot mix String and int values in the same enum',
              element: v,
            );
          }
          isStringValue = false;
          entries.add(
              _EnumEntry(v.name!, '${reader.intValue}', isString: false));
        } else {
          throw InvalidGenerationSourceError(
            '@CodecValue only supports String or int',
            element: v,
          );
        }
      }
    }

    // 部分挂 / 部分漏挂 → 漏挂值在运行时 encode 必抛 EncodeException，
    // 直接在 codegen 阶段拒绝，避免一直藏到生产才暴露。
    if (sawCodecValue) {
      final missing = validateCodecValueCoverage(
        allValues: [for (final v in values) v.name!],
        annotated: annotatedNames,
      );
      if (missing.isNotEmpty) {
        throw InvalidGenerationSourceError(
          '@CodecEnum $enumName has values missing @CodecValue: ${missing.join(', ')}. '
          'Either annotate every value, or remove all @CodecValue annotations to use the default .name / valueField mapping.',
          element: enumEl,
        );
      }
    }

    // 没有任何 @CodecValue：按 valueField 或 .name
    if (!sawCodecValue) {
      if (valueField != null) {
        return _generateValueFieldCodec(enumEl, codecVarName, valueField, values);
      }
      // 默认 .name
      final mapEntries = values
          .map((v) => "  '${v.name!}': $enumName.${v.name!},")
          .join('\n');
      final codecExpr = 'Codec.enumByName(const {\n$mapEntries\n})';
      return '''
// 按 .name 默认映射（$enumName 未挂 @CodecValue）。
final Codec<$enumName> $codecVarName = ${_applyStyle(codecExpr)};
''';
    }

    // 用 @CodecValue 的映射
    final mapEntries = entries
        .map((e) => '  ${e.literal}: $enumName.${e.dartName},')
        .join('\n');
    if (isStringValue == true) {
      // enumByName 默认按 .name 编码；显式 mapping 必须配对 toJson，
      // 否则 encode(qr) 会输出 'qr' 而非 @CodecValue 指定的 'QR'。
      final toJsonCases = entries
          .map((e) => '    $enumName.${e.dartName} => ${e.literal},')
          .join('\n');
      final codecExpr = 'Codec.enumByName(\n  const {\n$mapEntries\n  },\n'
          '  toJson: (e) => switch (e) {\n$toJsonCases\n  },\n)';
      return '''
// @CodecValue 映射（String），含双向 toJson。
final Codec<$enumName> $codecVarName = ${_applyStyle(codecExpr)};
''';
    }
    // int 映射
    final intCodecExpr =
        'Codec.enumOf<$enumName, int>(\n  Codec.integer,\n  const {\n$mapEntries\n  },\n)';
    return '''
// @CodecValue 映射（int）。
final Codec<$enumName> $codecVarName = ${_applyStyle(intCodecExpr)};
''';
  }

  String _generateValueFieldCodec(
    EnumElement enumEl,
    String codecVarName,
    String valueField,
    List<FieldElement> values,
  ) {
    final enumName = enumEl.name!;
    // 找 valueField 对应字段类型
    final field = enumEl.getField(valueField);
    if (field == null) {
      throw InvalidGenerationSourceError(
        "@CodecEnum(valueField: '$valueField') field '$valueField' not found on $enumName",
        element: enumEl,
      );
    }
    final fieldTypeStr = field.type.getDisplayString();
    final innerCodec = switch (fieldTypeStr) {
      'int' => 'Codec.integer',
      'String' => 'Codec.string',
      'double' => 'Codec.number',
      'num' => 'Codec.numeric',
      _ => throw InvalidGenerationSourceError(
          'valueField $valueField has unsupported type $fieldTypeStr (only int / String / double / num are supported)',
          element: enumEl,
        ),
    };

    final mapEntries = values
        .map((v) => '  $enumName.${v.name!}.$valueField: $enumName.${v.name!},')
        .join('\n');

    final codecExpr =
        'Codec.enumOf<$enumName, $fieldTypeStr>(\n  $innerCodec,\n  {\n$mapEntries\n  },\n)';
    return '''
// 按 ${enumEl.name!}.$valueField 字段映射。
// （Map 不带 const：enum 实例字段访问在 const 表达式里受限。）
final Codec<$enumName> $codecVarName = ${_applyStyle(codecExpr)};
''';
  }
}

class _EnumEntry {
  const _EnumEntry(this.dartName, this.literal, {required this.isString});
  final String dartName;
  final String literal;
  final bool isString;
}
