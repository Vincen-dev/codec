import 'package:codec_example/collections.dart';
import 'package:test/test.dart';

void main() {
  test('Collections — List/Map/可空元素/嵌套 往返', () {
    final json = {
      'ints': [1, 2, 3],
      'nullableStrings': ['a', null, 'c'],
      'points': [
        {'x': 1, 'y': 2},
        {'x': 3, 'y': 4},
      ],
      'scores': {'alice': 10, 'bob': 20},
      'maybePoints': {
        'p': {'x': 5, 'y': 6},
        'q': null,
      },
    };
    final m = Collections.fromJson(json);
    expect(m.ints, [1, 2, 3]);
    expect(m.nullableStrings, ['a', null, 'c']);
    expect(m.points.map((p) => p.x).toList(), [1, 3]);
    expect(m.scores['bob'], 20);
    expect(m.maybePoints['p']!.x, 5);
    expect(m.maybePoints['q'], isNull);
    expect(m.toJson(), json);
  });
}
