/// codec_gen builder 入口。被 `build.yaml` 注册为 SharedPartBuilder，
/// 与 json_serializable / freezed 等其他 generator 共享同一个 `xxx.g.dart`。
library;

import 'package:build/build.dart';
import 'package:codec/codec.dart';
import 'package:dart_style/dart_style.dart';
import 'package:source_gen/source_gen.dart';

import 'src/codable_generator.dart';
import 'src/codec_enum_generator.dart';

/// 生成 codec part 时使用的超宽 page width，等效“关闭软换行”。
///
/// codec part 是机器生成代码：reader 调用（`b.required/optional/optionalOr`）
/// 与枚举映射条目都作为单行表达式输出，而所有结构块（`Codec.object` 调用、
/// 构造器、encode map、枚举映射 map）一律自带尾随逗号来驱动换行。formatter
/// 只需在这些尾随逗号处换行即可，不应对单个表达式做软换行——一旦长类型名/
/// 长字段名让 reader 调用被软换行，其末尾缺尾随逗号就会触发
/// require_trailing_commas。把 page width 放到足够大，软换行不再发生，该 lint
/// 在生成代码里被“真正避免”，无需在消费侧 build.yaml 配 ignore_for_file。
const _generatedPageWidth = 1 << 16;

/// build.yaml 引用的 builder 工厂。
Builder codecBuilder(BuilderOptions options) {
  final raw = options.config['exception_style'];
  final format = switch (raw) {
    null || 'codec' => false,
    'format' => true,
    _ => throw ArgumentError(
        'codec_gen: unknown exception_style "$raw" (allowed: codec, format)'),
  };
  final renameRaw = options.config['field_rename'];
  final FieldRename? globalRename = switch (renameRaw) {
    null => null,
    'none' => FieldRename.none,
    'snake' => FieldRename.snake,
    'kebab' => FieldRename.kebab,
    'pascal' => FieldRename.pascal,
    'camel' => FieldRename.camel,
    'screamingSnake' => FieldRename.screamingSnake,
    _ => throw ArgumentError(
        'codec_gen: unknown field_rename "$renameRaw" '
        '(allowed: none, snake, kebab, pascal, camel, screamingSnake)'),
  };
  return SharedPartBuilder(
    [
      CodableGenerator(
        formatExceptions: format,
        defaultFieldRename: globalRename ?? FieldRename.none,
      ),
      CodecEnumGenerator(formatExceptions: format),
    ],
    'codec_gen',
    formatOutput: (code, version) =>
        DartFormatter(languageVersion: version, pageWidth: _generatedPageWidth)
            .format(code),
  );
}
