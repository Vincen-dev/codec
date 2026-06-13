// CodecEnumGenerator 的 golden test：验证各 @CodecEnum 形态下的生成代码，
// 以及 formatExceptions / exception_style 在顶层 codec 上的包装行为。
//
// 测试架构与 codable_generator_test.dart 完全一致：用 build_test 的
// [resolveSources] 拿到 LibraryElement，再直接调 generator。

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:codec_gen/src/codec_enum_generator.dart';
import 'package:source_gen/source_gen.dart';
import 'package:test/test.dart';

Future<String> _generateWith(
  String source,
  CodecEnumGenerator gen,
) async {
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
        const TypeChecker.typeNamedLiterally('CodecEnum', inPackage: 'codec'),
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

Future<String> _generate(String source) =>
    _generateWith(source, CodecEnumGenerator());

/// generator 不调用 BuildStep 上任何方法；用 noSuchMethod 兜底。
class _FakeBuildStep implements BuildStep {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// ---------------------------------------------------------------------------
// 基础生成形态（formatExceptions 默认为 false）
// ---------------------------------------------------------------------------

void main() {
  group('CodecEnumGenerator — 基础生成形态', () {
    test('默认 .name 映射', () async {
      final out = await _generate('''
import 'package:codec/codec.dart';
@CodecEnum()
enum Color { red, green, blue }
''');
      expect(out, contains('Codec.enumByName('));
      expect(out, contains("'red': Color.red,"));
      expect(out, contains('final Codec<Color> _\$colorCodec'));
      expect(out, isNot(contains('.withFormatExceptions()')));
    });

    test('@CodecEnum(valueField:) 生成 Codec.enumOf', () async {
      final out = await _generate('''
import 'package:codec/codec.dart';
@CodecEnum(valueField: 'code')
enum Status {
  active(1), inactive(0);
  const Status(this.code);
  final int code;
}
''');
      expect(out, contains('Codec.enumOf<Status, int>('));
      expect(out, contains('Codec.integer,'));
      expect(out, contains('Status.active.code: Status.active,'));
      expect(out, isNot(contains('.withFormatExceptions()')));
    });

    test('@CodecValue String → enumByName + toJson', () async {
      final out = await _generate('''
import 'package:codec/codec.dart';
@CodecEnum()
enum Direction {
  @CodecValue('N') north,
  @CodecValue('S') south,
}
''');
      expect(out, contains('toJson:'));
      expect(out, contains("'N': Direction.north,"));
      expect(out, isNot(contains('.withFormatExceptions()')));
    });

    test('@CodecValue int → enumOf<E, int>', () async {
      final out = await _generate('''
import 'package:codec/codec.dart';
@CodecEnum()
enum Priority {
  @CodecValue(1) high,
  @CodecValue(0) low,
}
''');
      expect(out, contains('Codec.enumOf<Priority, int>('));
      expect(out, isNot(contains('.withFormatExceptions()')));
    });
  });

  // ---------------------------------------------------------------------------
  // formatExceptions / exception_style 包装行为
  // ---------------------------------------------------------------------------

  group('CodecEnumGenerator — formatExceptions / exception_style', () {
    test('formatExceptions: true + 默认 .name → 顶层含 .withFormatExceptions()',
        () async {
      final out = await _generateWith(
        '''
import 'package:codec/codec.dart';
@CodecEnum()
enum Color { red, green, blue }
''',
        CodecEnumGenerator(formatExceptions: true),
      );
      expect(out, contains('.withFormatExceptions()'));
      expect(out, contains('final Codec<Color> _\$colorCodec ='));
    });

    test('formatExceptions: false（default） + 默认 .name → 不含 .withFormatExceptions()',
        () async {
      final out = await _generateWith(
        '''
import 'package:codec/codec.dart';
@CodecEnum()
enum Color { red, green, blue }
''',
        CodecEnumGenerator(formatExceptions: false),
      );
      expect(out, isNot(contains('.withFormatExceptions()')));
    });

    test('formatExceptions: true + @CodecEnum(valueField:) → 顶层含 .withFormatExceptions()',
        () async {
      final out = await _generateWith(
        '''
import 'package:codec/codec.dart';
@CodecEnum(valueField: 'code')
enum Status {
  active(1), inactive(0);
  const Status(this.code);
  final int code;
}
''',
        CodecEnumGenerator(formatExceptions: true),
      );
      expect(out, contains('.withFormatExceptions()'));
    });

    test('formatExceptions: true + @CodecValue String → 顶层含 .withFormatExceptions()',
        () async {
      final out = await _generateWith(
        '''
import 'package:codec/codec.dart';
@CodecEnum()
enum Direction {
  @CodecValue('N') north,
  @CodecValue('S') south,
}
''',
        CodecEnumGenerator(formatExceptions: true),
      );
      expect(out, contains('.withFormatExceptions()'));
    });

    test('formatExceptions: true + @CodecValue int → 顶层含 .withFormatExceptions()',
        () async {
      final out = await _generateWith(
        '''
import 'package:codec/codec.dart';
@CodecEnum()
enum Priority {
  @CodecValue(1) high,
  @CodecValue(0) low,
}
''',
        CodecEnumGenerator(formatExceptions: true),
      );
      expect(out, contains('.withFormatExceptions()'));
    });
  });
}
