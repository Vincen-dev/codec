// codecBuilder 的 build.yaml 选项解析测试：field_rename 合法 token 通过、
// 非法 token 在构造 builder 时抛 ArgumentError；与既有 exception_style 校验并存。
import 'package:build/build.dart';
import 'package:codec_gen/codec_gen.dart';
import 'package:test/test.dart';

void main() {
  group('codecBuilder — field_rename 选项', () {
    test('合法 token 返回 Builder', () {
      expect(codecBuilder(BuilderOptions({'field_rename': 'snake'})), isA<Builder>());
      expect(codecBuilder(BuilderOptions({'field_rename': 'screamingSnake'})),
          isA<Builder>());
      expect(codecBuilder(BuilderOptions({})), isA<Builder>()); // 缺省可接受
    });

    test('非法 token 抛 ArgumentError', () {
      expect(
        () => codecBuilder(BuilderOptions({'field_rename': 'bogus'})),
        throwsArgumentError,
      );
    });

    test('exception_style 仍独立校验', () {
      expect(
        () => codecBuilder(BuilderOptions({'exception_style': 'bogus'})),
        throwsArgumentError,
      );
    });
  });
}
