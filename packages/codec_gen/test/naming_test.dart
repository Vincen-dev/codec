import 'package:codec/codec.dart';
import 'package:codec_gen/src/naming.dart';
import 'package:test/test.dart';

void main() {
  group('renameField — none/camel 透传', () {
    test('none 保持原样', () {
      expect(renameField('userName', FieldRename.none), 'userName');
      expect(renameField('URL', FieldRename.none), 'URL');
    });

    test('camel 等同 none', () {
      expect(renameField('userName', FieldRename.camel), 'userName');
    });

    test('空字符串', () {
      expect(renameField('', FieldRename.snake), '');
      expect(renameField('', FieldRename.kebab), '');
      expect(renameField('', FieldRename.pascal), '');
    });
  });

  group('renameField — snake 极限场景', () {
    test('单词不变', () {
      expect(renameField('user', FieldRename.snake), 'user');
      expect(renameField('x', FieldRename.snake), 'x');
    });

    test('简单 camelCase', () {
      expect(renameField('userName', FieldRename.snake), 'user_name');
      expect(renameField('totalAmount', FieldRename.snake), 'total_amount');
    });

    test('末尾连续大写：userID → user_id', () {
      expect(renameField('userID', FieldRename.snake), 'user_id');
    });

    test('开头连续大写：URLPath → url_path', () {
      expect(renameField('URLPath', FieldRename.snake), 'url_path');
    });

    test('中间连续大写：userIDValue → user_id_value', () {
      expect(renameField('userIDValue', FieldRename.snake), 'user_id_value');
    });

    test('整体全大写：URL → url', () {
      expect(renameField('URL', FieldRename.snake), 'url');
    });

    test('多段连续大写无内嵌边界：parseHTTPURLPath → parse_httpurl_path', () {
      // 注：纯字符串无法识别 HTTPURL 是 HTTP+URL 还是单词，与
      // Lodash / inflection 等主流实现一致——把连续大写视为单个词。
      expect(
        renameField('parseHTTPURLPath', FieldRename.snake),
        'parse_httpurl_path',
      );
    });

    test('单字母大写词夹中间：aBC → a_bc / iOS → i_os', () {
      expect(renameField('aBC', FieldRename.snake), 'a_bc');
      expect(renameField('iOS', FieldRename.snake), 'i_os');
    });

    test('数字不切词：user2name → user2name（保留现状语义）', () {
      // 当前实现把数字当作 lower（无 upper-lower 边界），不切。
      // 锁定行为，避免无意中改动语义。
      expect(renameField('user2name', FieldRename.snake), 'user2name');
    });
  });

  group('renameField — kebab', () {
    test('与 snake 同分词，分隔符为 -', () {
      expect(renameField('userName', FieldRename.kebab), 'user-name');
      expect(renameField('userIDValue', FieldRename.kebab), 'user-id-value');
      expect(renameField('URLPath', FieldRename.kebab), 'url-path');
    });
  });

  group('renameField — pascal', () {
    test('camelCase → PascalCase', () {
      expect(renameField('userName', FieldRename.pascal), 'UserName');
    });

    test('连续大写正确归并：userIDValue → UserIdValue', () {
      expect(renameField('userIDValue', FieldRename.pascal), 'UserIdValue');
    });
  });

  group('renameField — screamingSnake', () {
    test('camelCase → SCREAMING_SNAKE', () {
      expect(
        renameField('userName', FieldRename.screamingSnake),
        'USER_NAME',
      );
      expect(
        renameField('totalAmount', FieldRename.screamingSnake),
        'TOTAL_AMOUNT',
      );
    });

    test('连续大写：userIDValue → USER_ID_VALUE', () {
      expect(
        renameField('userIDValue', FieldRename.screamingSnake),
        'USER_ID_VALUE',
      );
    });

    test('整体已是大写词：URL → URL', () {
      expect(
        renameField('URL', FieldRename.screamingSnake),
        'URL',
      );
    });

    test('单词：x → X', () {
      expect(renameField('x', FieldRename.screamingSnake), 'X');
    });

    test('空字符串', () {
      expect(renameField('', FieldRename.screamingSnake), '');
    });

    test('开头连续大写：URLPath → URL_PATH', () {
      expect(
        renameField('URLPath', FieldRename.screamingSnake),
        'URL_PATH',
      );
    });
  });

  group('lowerFirst', () {
    test('UserName → userName', () {
      expect(lowerFirst('UserName'), 'userName');
    });

    test('userName 不变', () {
      expect(lowerFirst('userName'), 'userName');
    });

    test('单字符 X → x', () {
      expect(lowerFirst('X'), 'x');
    });

    test('空字符串', () {
      expect(lowerFirst(''), '');
    });
  });

  group('dartStringLiteral — 转义', () {
    test('普通 ASCII 单引号包裹', () {
      expect(dartStringLiteral('hello'), "'hello'");
    });

    test('空字符串', () {
      expect(dartStringLiteral(''), "''");
    });

    test('单引号必须转义（避免破坏字面量）', () {
      expect(dartStringLiteral("It's"), r"'It\'s'");
    });

    test('反斜杠必须先转义', () {
      expect(dartStringLiteral(r'a\b'), r"'a\\b'");
    });

    test('美元符号必须转义（避免插值）', () {
      expect(dartStringLiteral(r'a$b'), r"'a\$b'");
      expect(dartStringLiteral(r'${var}'), r"'\${var}'");
    });

    test('换行 / 回车 / TAB 转义为可见序列', () {
      expect(dartStringLiteral('a\nb'), r"'a\nb'");
      expect(dartStringLiteral('a\rb'), r"'a\rb'");
      expect(dartStringLiteral('a\tb'), r"'a\tb'");
    });

    test('混合极限：It\'s a \$5\\dollar\\n', () {
      expect(
        dartStringLiteral("It's a \$5\\dollar\n"),
        r"'It\'s a \$5\\dollar\n'",
      );
    });

    test('反斜杠先于其他转义（顺序敏感）', () {
      // 输入 a\n（反斜杠 + 字符 n），不是真换行
      // 期望输出 'a\\n'（双反斜杠 + n），而不是错误地变成 'a\n'
      expect(dartStringLiteral(r'a\n'), r"'a\\n'");
    });

    test('双引号无需转义（用单引号包裹）', () {
      expect(dartStringLiteral('he said "hi"'), '\'he said "hi"\'');
    });

    test('Unicode 字符原样保留', () {
      expect(dartStringLiteral('日本語'), "'日本語'");
      expect(dartStringLiteral('🎉'), "'🎉'");
    });
  });
}
