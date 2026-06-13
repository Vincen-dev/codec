import 'package:codec/codec.dart';

/// 把 dart 字段名按 [FieldRename] 转成 JSON 字段名。
String renameField(String dartName, FieldRename strategy) {
  return switch (strategy) {
    FieldRename.none || FieldRename.camel => dartName,
    FieldRename.snake => _toSnake(dartName),
    FieldRename.kebab => _toKebab(dartName),
    FieldRename.pascal => _toPascal(dartName),
    FieldRename.screamingSnake => _toScreamingSnake(dartName),
  };
}

/// `userName` → `userName`；`UserName` → `userName`。
String lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// `userName` → `UserName`；用于拼装 helper 变量名时首字母大写。
String upperFirst(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// 把任意字符串转换为合法的 dart 单引号字符串字面量。
///
/// 用于 codegen 把用户提供的字符串值（`@CodecValue` / `@CodecField.defaultValue`）
/// 安全地 inline 到生成代码里——直接 `"'${v}'"` 拼接遇到 `'` / `\` / `$` 会
/// 产生不能编译的代码或意外的字符串插值。
///
/// 转义顺序：先 `\`，再单引号 / `$` / 控制字符。BMP 与代理对原样保留。
String dartStringLiteral(String s) {
  final buf = StringBuffer("'");
  for (final code in s.codeUnits) {
    switch (code) {
      case 0x5C: // \
        buf.write(r'\\');
      case 0x27: // '
        buf.write(r"\'");
      case 0x24: // $
        buf.write(r'\$');
      case 0x0A: // \n
        buf.write(r'\n');
      case 0x0D: // \r
        buf.write(r'\r');
      case 0x09: // \t
        buf.write(r'\t');
      default:
        buf.writeCharCode(code);
    }
  }
  buf.write("'");
  return buf.toString();
}

String _toSnake(String s) =>
    _splitWords(s).map((w) => w.toLowerCase()).join('_');
String _toKebab(String s) =>
    _splitWords(s).map((w) => w.toLowerCase()).join('-');
String _toScreamingSnake(String s) =>
    _splitWords(s).map((w) => w.toUpperCase()).join('_');
String _toPascal(String s) => _splitWords(s)
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join();

/// 切分 camelCase / PascalCase 字符串。
///
/// 切分规则：
/// - lower → upper：`userName` 在 `N` 处起新词
/// - upper → upper → lower：`IDValue` 在 `V` 处起新词（lookahead 1）
///
/// 连续大写无内嵌 lower 时视为单个词（`URL` → `[URL]`，`HTTPURL` →
/// `[HTTPURL]`）——纯字符串无法识别这种内嵌边界，与 Lodash / inflection
/// 等主流实现一致。
List<String> _splitWords(String s) {
  if (s.isEmpty) return const [];
  final result = <String>[];
  final buf = StringBuffer()..write(s[0]);
  for (var i = 1; i < s.length; i++) {
    final ch = s[i];
    final prev = s[i - 1];
    final next = i + 1 < s.length ? s[i + 1] : null;
    final isUpper = ch == ch.toUpperCase() && ch != ch.toLowerCase();
    final prevIsUpper =
        prev == prev.toUpperCase() && prev != prev.toLowerCase();
    final nextIsLower = next != null &&
        next == next.toLowerCase() &&
        next != next.toUpperCase();
    // (a) prev lower, ch upper      → 起新词（userName / userID）
    // (b) prev upper, ch upper, next lower → 起新词（IDValue → ID|Value）
    final boundary =
        isUpper && (!prevIsUpper || nextIsLower);
    if (boundary) {
      result.add(buf.toString());
      buf.clear();
    }
    buf.write(ch);
  }
  if (buf.isNotEmpty) result.add(buf.toString());
  return result;
}
