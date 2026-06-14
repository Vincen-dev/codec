// CodableGenerator 的 golden test：验证 `b.required<T>` / `b.optional<T>` /
// `b.optionalOr<T>` 显式泛型一定被注入到生成代码里。
//
// 与 build_runner 全量重生成 + analyze 的"端到端"验证互补：这一层把
// generator 字符串拼装隔离出来单测，遇到回归（比如 Codec.any 类的
// nullable T 推断坑再次出现）能秒级反馈，不用等几分钟的 build_runner。
//
// 实现思路：用 build_test 的 [resolveSources] 拿到一段 dart 源码对应的
// LibraryElement，再用 [LibraryReader.annotatedWith] 抓 @Codable class，
// 直接调 [CodableGenerator.generateForAnnotatedElement] 拿到生成字符串。
// generator 不消费 BuildStep，传一个 noSuchMethod fake 就够。

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:codec/codec.dart';
import 'package:codec_gen/src/codable_generator.dart';
import 'package:source_gen/source_gen.dart';
import 'package:test/test.dart';

Future<String> _generate(String source) => _generateWith(
      source,
      CodableGenerator(),
    );

Future<String> _generateWith(String source, CodableGenerator gen) async {
  late String output;
  await resolveSources(
    {'codec_gen|test/_input.dart': source},
    (resolver) async {
      final lib = await resolver.libraryFor(
        AssetId('codec_gen', 'test/_input.dart'),
      );
      final reader = LibraryReader(lib);
      final hits = <String>[];
      for (final annotated in reader.annotatedWith(
        const TypeChecker.typeNamedLiterally('Codable', inPackage: 'codec'),
      )) {
        hits.add(gen.generateForAnnotatedElement(
          annotated.element,
          annotated.annotation,
          _FakeBuildStep(),
        ));
      }
      output = hits.join('\n\n');
    },
    readAllSourcesFromFilesystem: true,
  );
  return output;
}

/// generator 不调用 BuildStep 上任何方法；用 noSuchMethod 兜底，避免
/// 引入 mockito / mocktail 单纯为了 mock 一个空对象。
class _FakeBuildStep implements BuildStep {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('CodableGenerator — 显式泛型注入', () {
    test('原语 non-nullable 字段 → b.required<T>', () async {
      final out = await _generate('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  final int code;
  const M({required this.code});
}
''');
      expect(out, contains("b.required<int>('code', Codec.integer)"));
    });

    test('原语 nullable 字段 → b.optional<T>（T 不带 ?）', () async {
      final out = await _generate('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  final String? message;
  const M({this.message});
}
''');
      // b.optional<T>(...) 返回 T?；T 用 codec 的 T（非 nullable 形态）
      expect(out, contains("b.optional<String>('message', Codec.string)"));
    });

    test('Object? 字段 → b.optional<Object?> + Codec.any', () async {
      // 这是当初触发本套显式泛型方案的核心场景：Codec.any 是 Codec<Object?>，
      // 编译器从字段类型反推 T=Object 会与 codec 不匹配，必须显式 <Object?>。
      final out = await _generate('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  final Object? data;
  const M({this.data});
}
''');
      expect(out, contains("b.optional<Object?>('data', Codec.any)"));
    });

    test('dynamic 字段 → b.required<Object?> + Codec.any', () async {
      // dynamic 在 Dart 类型系统里 nullabilitySuffix 为 none，generator 不
      // 走 b.optional 而走 b.required；codec 仍是 Codec.any (Codec<Object?>)，
      // typeArg 也必须显式 <Object?>。
      final out = await _generate('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  final dynamic data;
  const M({required this.data});
}
''');
      expect(out, contains("b.required<Object?>('data', Codec.any)"));
    });

    test('List<T>? 字段保留外层 + 元素类型', () async {
      final out = await _generate('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  final List<String>? tags;
  const M({this.tags});
}
''');
      expect(
        out,
        contains("b.optional<List<String>>('tags', Codec.string.list())"),
      );
    });

    test('List<int?>? 嵌套可空元素 → 元素 codec 加 .nullable()，typeArg 同步', () async {
      final out = await _generate('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  final List<int?>? values;
  const M({this.values});
}
''');
      expect(out, contains("b.optional<List<int?>>"));
      expect(out, contains('Codec.integer.nullable().list()'));
    });

    test('Map<String, V> 字段', () async {
      final out = await _generate('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  final Map<String, int>? counts;
  const M({this.counts});
}
''');
      expect(
        out,
        contains(
          "b.optional<Map<String, int>>('counts', Codec.mapOf(Codec.integer))",
        ),
      );
    });

    test('@CodecField(defaultValue:) → b.optionalOr<T>', () async {
      final out = await _generate('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  @CodecField(defaultValue: 0)
  final int count;
  const M({required this.count});
}
''');
      expect(
        out,
        contains("b.optionalOr<int>('count', Codec.integer, 0)"),
      );
    });

    test('nullable + required → b.required<T?>(.., codec.nullable() wrapper)', () async {
      final out = await _generate('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  @CodecField(required: true)
  final String? code;
  const M({this.code});
}
''');
      expect(out, contains("b.required<String?>('code',"));
      expect(out, contains('Codec.string.nullable()'));
    });

    test('Codec.any + nullable + required → T 仍是 Object?（不双重 nullable）', () async {
      // 关键：nullify('Object?') 必须保持 'Object?'，不重复加 `?` 生成
      // `Object??` 这种合法但难读的形态。
      final out = await _generate('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  @CodecField(required: true)
  final Object? data;
  const M({this.data});
}
''');
      expect(out, contains("b.required<Object?>('data',"));
      expect(out, contains('Codec.any.nullable()'));
      expect(out, isNot(contains('Object??')));
    });

    test('@CodecField(dateTime: DateTimeMode.utc) → Codec.dateTimeUtc + T=DateTime', () async {
      final out = await _generate('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  @CodecField(dateTime: DateTimeMode.utc)
  final DateTime createdAt;
  const M({required this.createdAt});
}
''');
      expect(
        out,
        contains("b.required<DateTime>('createdAt', Codec.dateTimeUtc)"),
      );
    });

    test('@CodecField(codec: \'_custom\') → typeArg 用字段类型 strip nullable', () async {
      // 自定义 codec 路径 generator 不知道 codec 的 T，约定用字段类型
      // strip nullable 作为 fallback，用户负责 codec T 与字段类型一致。
      final out = await _generate('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  @CodecField(codec: '_priceCodec')
  final double? price;
  const M({this.price});
}
''');
      expect(
        out,
        contains("b.optional<double>('price', _priceCodec)"),
      );
    });

    test('enum 字段（未挂 @CodecEnum）inline Codec.enumByName + T=Enum 名', () async {
      final out = await _generate('''
import 'package:codec/codec.dart';

enum Color { red, green, blue }

@Codable()
final class M {
  final Color? color;
  const M({this.color});
}
''');
      // inline enumByName 含 'red'/'green'/'blue'
      expect(out, contains("b.optional<Color>('color', Codec.enumByName("));
      expect(out, contains("'red': Color.red"));
    });

    test('non-null 无 default → 等价必填，输出 b.required<T>', () async {
      final out = await _generate('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  final String name;
  const M({required this.name});
}
''');
      expect(out, contains("b.required<String>('name', Codec.string)"));
    });
  });

  group('CodableGenerator — @CodecField(enumValueField:)', () {
    test('int valueField → 顶层 helper(Codec.enumOf<E,int>) + 字段引用 helper',
        () async {
      final out = await _generate('''
import 'package:codec/codec.dart';

enum OrderState {
  pending(1), paid(3);
  const OrderState(this.code);
  final int code;
}

@Codable()
final class M {
  @CodecField(enumValueField: 'code')
  final OrderState orderState;
  const M({required this.orderState});
}
''');
      // 顶层 helper 声明 + 内层 Codec.integer + 按 .code 的映射条目
      expect(
        out,
        contains(
          'final Codec<OrderState> _\$mOrderStateEnumCodec = '
          'Codec.enumOf<OrderState, int>(',
        ),
      );
      expect(out, contains('Codec.integer,'));
      expect(out, contains('OrderState.pending.code: OrderState.pending,'));
      // 字段读取引用 helper，而非 inline enumByName
      expect(
        out,
        contains("b.required<OrderState>('orderState', _\$mOrderStateEnumCodec)"),
      );
      expect(out, isNot(contains('Codec.enumByName(')));
    });

    test('String valueField → 内层 Codec.string', () async {
      final out = await _generate('''
import 'package:codec/codec.dart';

enum Color {
  red('R'), green('G');
  const Color(this.tag);
  final String tag;
}

@Codable()
final class M {
  @CodecField(enumValueField: 'tag')
  final Color color;
  const M({required this.color});
}
''');
      expect(
        out,
        contains(
          'final Codec<Color> _\$mColorEnumCodec = '
          'Codec.enumOf<Color, String>(',
        ),
      );
      expect(out, contains('Codec.string,'));
      expect(out, contains('Color.red.tag: Color.red,'));
    });

    test('同文件多个 @Codable 引用同一枚举 → helper 按类+字段命名各自唯一',
        () async {
      final out = await _generate('''
import 'package:codec/codec.dart';

enum OrderState {
  pending(1), paid(3);
  const OrderState(this.code);
  final int code;
}

@Codable()
final class M {
  @CodecField(enumValueField: 'code')
  final OrderState orderState;
  const M({required this.orderState});
}

@Codable()
final class N {
  @CodecField(enumValueField: 'code')
  final OrderState orderState;
  const N({required this.orderState});
}
''');
      expect(out, contains('_\$mOrderStateEnumCodec'));
      expect(out, contains('_\$nOrderStateEnumCodec'));
    });

    test('enumValueField 用于非 enum 字段 → 抛 InvalidGenerationSourceError',
        () async {
      await expectLater(
        _generate('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  @CodecField(enumValueField: 'code')
  final String name;
  const M({required this.name});
}
'''),
        throwsA(isA<InvalidGenerationSourceError>()),
      );
    });

    test('valueField 类型不支持(bool) → 抛 InvalidGenerationSourceError',
        () async {
      await expectLater(
        _generate('''
import 'package:codec/codec.dart';

enum Flag {
  on(true), off(false);
  const Flag(this.active);
  final bool active;
}

@Codable()
final class M {
  @CodecField(enumValueField: 'active')
  final Flag flag;
  const M({required this.flag});
}
'''),
        throwsA(isA<InvalidGenerationSourceError>()),
      );
    });

    test('enumValueField + unknownEnumValue → enumOf 带 unknownFallback',
        () async {
      final out = await _generate('''
import 'package:codec/codec.dart';

enum Area {
  hk(84), jp(99);
  const Area(this.code);
  final int code;
}

@Codable()
final class M {
  @CodecField(enumValueField: 'code', unknownEnumValue: Area.hk)
  final Area area;
  const M({this.area = Area.hk});
}
''');
      expect(out, contains('Codec.enumOf<Area, int>('));
      expect(out, contains('unknownFallback: Area.hk,'));
    });

    test('unknownEnumValue 脱离 enumValueField → 抛 InvalidGenerationSourceError',
        () async {
      await expectLater(
        _generate('''
import 'package:codec/codec.dart';

enum Area { hk, jp }

@Codable()
final class M {
  @CodecField(unknownEnumValue: Area.hk)
  final Area area;
  const M({this.area = Area.hk});
}
'''),
        throwsA(isA<InvalidGenerationSourceError>()),
      );
    });

    test('unknownEnumValue 枚举类型与字段不一致 → 抛 InvalidGenerationSourceError',
        () async {
      await expectLater(
        _generate('''
import 'package:codec/codec.dart';

enum Area {
  hk(84), jp(99);
  const Area(this.code);
  final int code;
}

enum Other { a, b }

@Codable()
final class M {
  @CodecField(enumValueField: 'code', unknownEnumValue: Other.a)
  final Area area;
  const M({this.area = Area.hk});
}
'''),
        throwsA(isA<InvalidGenerationSourceError>()),
      );
    });
  });

  group('CodableGenerator — JSON key escaping (G1)', () {
    test("@CodecField(name:) 含单引号与 \$ 字符 → 生成代码中 key 正确转义", () async {
      final out = await _generate(r'''
import 'package:codec/codec.dart';
@Codable()
final class M {
  @CodecField(name: "we'ird\$key")
  final String value;
  const M({required this.value});
}
''');
      // 应含转义后的 key 字面量（单引号转义为 \'，$ 转义为 \$）
      expect(out, contains(r"'we\'ird\$key'"),
          reason: '生成代码中 key 中的单引号和 \$ 应被转义');
      // 不应有未转义的单引号导致的字符串断裂（如 'we'ird）
      expect(out, isNot(contains("'we'ird")),
          reason: '不应有未转义的单引号断裂字符串');
    });

    test("普通 key（标识符形式）→ 生成代码不受影响", () async {
      final out = await _generate('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  final String name;
  const M({required this.name});
}
''');
      // 正常 key 生成结果保持不变
      expect(out, contains("b.required<String>('name', Codec.string)"));
    });
  });

  group('CodableGenerator — formatExceptions / exception_style', () {
    const simpleSource = '''
import 'package:codec/codec.dart';
@Codable()
final class M {
  final int code;
  const M({required this.code});
}
''';

    test('formatExceptions: true → 顶层 codec 末尾含 .withFormatExceptions()',
        () async {
      final out = await _generateWith(
        simpleSource,
        CodableGenerator(formatExceptions: true),
      );
      expect(out, contains('.withFormatExceptions()'));
      // 顶层声明以 ).withFormatExceptions() 结尾
      expect(
        out,
        contains(
          'final Codec<M> _\$mCodec = (Codec.object<M>(',
        ),
      );
      expect(out, contains(')).withFormatExceptions()'));
    });

    test('formatExceptions: false（default）→ 不含 .withFormatExceptions()',
        () async {
      final out = await _generateWith(
        simpleSource,
        CodableGenerator(formatExceptions: false),
      );
      expect(out, isNot(contains('.withFormatExceptions()')));
    });

    test(
        'formatExceptions: true + IIFE 路径（nullable wrapper）→ '
        '.withFormatExceptions() 恰出现一次且包裹 IIFE 结果', () async {
      // includeIfNull: true 使 omitWhenNull=false；nullable 字段进入 encode 侧的
      // wrapperFor 调用，nullableWrappers 非空 → 走 IIFE 路径。
      final out = await _generateWith(
        '''
import 'package:codec/codec.dart';
@Codable(includeIfNull: true)
final class M {
  final String? note;
  const M({this.note});
}
''',
        CodableGenerator(formatExceptions: true),
      );

      // 确认真正走了 IIFE 路径（而非 simple 路径）
      expect(out, contains('(() {'),
          reason: '应产出 IIFE 语法（nullableWrappers 非空）');
      expect(out, contains('})()'),
          reason: '应有 IIFE 收尾 })()');


      // .withFormatExceptions() 恰好出现一次
      final count = '.withFormatExceptions()'.allMatches(out).length;
      expect(count, 1,
          reason: '.withFormatExceptions() 应恰好出现一次');

      // IIFE 结果被包裹：_applyStyle(iife) → (iife).withFormatExceptions()，
      // 即 ((() { ... })()).withFormatExceptions()，闭合形态为 })()).withFormatExceptions()
      expect(out, contains('})()).withFormatExceptions()'),
          reason: '.withFormatExceptions() 应直接跟在包裹 IIFE 的外层括号之后');
    });

    test(
        'formatExceptions: true + enumValueField helper → '
        '.withFormatExceptions() 仅出现一次（helper 不受影响）', () async {
      final out = await _generateWith(
        '''
import 'package:codec/codec.dart';

enum OrderState {
  pending(1), paid(3);
  const OrderState(this.code);
  final int code;
}

@Codable()
final class M {
  @CodecField(enumValueField: 'code')
  final OrderState orderState;
  const M({required this.orderState});
}
''',
        CodableGenerator(formatExceptions: true),
      );
      // .withFormatExceptions() 仅出现在顶层 _$mCodec，helper 行不含
      expect(out, contains('.withFormatExceptions()'));
      final count =
          '.withFormatExceptions()'.allMatches(out).length;
      expect(count, 1,
          reason: 'helper 不应被包装，顶层 codec 恰好出现一次');
      // helper 行不含 withFormatExceptions
      final helperLine = out
          .split('\n')
          .firstWhere((l) => l.contains('_\$mOrderStateEnumCodec'));
      expect(helperLine, isNot(contains('.withFormatExceptions()')));
    });
  });

  group('CodableGenerator — 全局 field_rename', () {
    test('全局 snake：@Codable() 无 fieldRename → key 变 snake', () async {
      final out = await _generateWith('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  final String userName;
  const M({required this.userName});
}
''', CodableGenerator(defaultFieldRename: FieldRename.snake));
      expect(out, contains("b.required<String>('user_name', Codec.string)"));
      expect(out, contains("'user_name': Codec.string.encode(v.userName)"));
    });

    test('类级 fieldRename 覆盖全局：全局 snake + 类级 kebab → kebab', () async {
      final out = await _generateWith('''
import 'package:codec/codec.dart';
@Codable(fieldRename: FieldRename.kebab)
final class M {
  final String userName;
  const M({required this.userName});
}
''', CodableGenerator(defaultFieldRename: FieldRename.snake));
      expect(out, contains("b.required<String>('user-name', Codec.string)"));
      expect(out, isNot(contains("'user_name'")));
    });

    test('显式 none 覆盖全局：全局 snake + 类级 none → 不改名', () async {
      final out = await _generateWith('''
import 'package:codec/codec.dart';
@Codable(fieldRename: FieldRename.none)
final class M {
  final String userName;
  const M({required this.userName});
}
''', CodableGenerator(defaultFieldRename: FieldRename.snake));
      expect(out, contains("b.required<String>('userName', Codec.string)"));
      expect(out, isNot(contains("'user_name'")));
    });

    test('字段级 name 仍最高：全局 snake + @CodecField(name:) → 用显式名', () async {
      final out = await _generateWith('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  @CodecField(name: 'EXPLICIT')
  final String userName;
  const M({required this.userName});
}
''', CodableGenerator(defaultFieldRename: FieldRename.snake));
      expect(out, contains("'EXPLICIT'"));
      expect(out, isNot(contains("'user_name'")));
    });

    test('无全局（默认）回归：@Codable() → 不改名', () async {
      final out = await _generate('''
import 'package:codec/codec.dart';
@Codable()
final class M {
  final String userName;
  const M({required this.userName});
}
''');
      expect(out, contains("'userName'"));
      expect(out, contains("'userName': Codec.string.encode(v.userName)"));
    });
  });
}
