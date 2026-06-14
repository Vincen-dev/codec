import 'package:codec_example/nested.dart';
import 'package:test/test.dart';

void main() {
  test('Parent — 嵌套模型 + 自定义 codec（decode 小写 / encode 大写）', () {
    final p = Parent.fromJson({
      'child': {'label': 'hi'},
      'code': 'ABC',
    });
    expect(p.child.label, 'hi');
    expect(p.code, 'abc'); // _shoutCodec decode 小写
    expect(p.toJson(), {
      'child': {'label': 'hi'},
      'code': 'ABC', // encode 大写
    });
  });

  test('Tree — 自引用递归往返', () {
    final t = Tree.fromJson({
      'value': 1,
      'children': [
        {'value': 2},
        {
          'value': 3,
          'children': [
            {'value': 4},
          ],
        },
      ],
    });
    expect(t.value, 1);
    expect(t.children.length, 2);
    expect(t.children[1].children.single.value, 4);
    // children 非空有默认 const []，叶子节点 encode 出 'children': []
    expect(t.toJson(), {
      'value': 1,
      'children': [
        {'value': 2, 'children': <Object?>[]},
        {
          'value': 3,
          'children': [
            {'value': 4, 'children': <Object?>[]},
          ],
        },
      ],
    });
  });
}
