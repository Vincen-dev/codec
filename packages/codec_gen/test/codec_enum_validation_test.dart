import 'package:codec_gen/src/codec_enum_validation.dart';
import 'package:test/test.dart';

void main() {
  group('validateCodecValueCoverage', () {
    test('全部值都挂 @CodecValue：返回空 missing', () {
      expect(
        validateCodecValueCoverage(
          allValues: const ['a', 'b', 'c'],
          annotated: const {'a', 'b', 'c'},
        ),
        isEmpty,
      );
    });

    test('全部都没挂：返回空 missing（外层判定走默认 .name 路径，不触发校验）', () {
      // 校验函数自身只关心"局部漏挂"——全没挂是另一种合法路径
      expect(
        validateCodecValueCoverage(
          allValues: const ['a', 'b', 'c'],
          annotated: const {},
        ),
        isEmpty,
      );
    });

    test('部分挂部分没挂：返回漏挂的值，按原顺序', () {
      expect(
        validateCodecValueCoverage(
          allValues: const ['a', 'b', 'c', 'd'],
          annotated: const {'a', 'c'},
        ),
        ['b', 'd'],
      );
    });

    test('单个漏挂', () {
      expect(
        validateCodecValueCoverage(
          allValues: const ['a', 'b', 'c'],
          annotated: const {'a', 'b'},
        ),
        ['c'],
      );
    });

    test('空 enum：空 missing', () {
      expect(
        validateCodecValueCoverage(
          allValues: const [],
          annotated: const {},
        ),
        isEmpty,
      );
    });

    test('annotated 含未在 allValues 中的值（理论上不可能但要稳）', () {
      // 不报错，只看 allValues 中谁未被标注
      expect(
        validateCodecValueCoverage(
          allValues: const ['a', 'b'],
          annotated: const {'a', 'phantom'},
        ),
        ['b'],
      );
    });

    test('保留 allValues 顺序，不排序', () {
      expect(
        validateCodecValueCoverage(
          allValues: const ['z', 'a', 'm'],
          annotated: const {'a'},
        ),
        ['z', 'm'],
      );
    });
  });
}
