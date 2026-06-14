import 'package:codec/codec.dart';

part 'collections.g.dart';

@Codable()
final class Point {
  const Point({required this.x, required this.y});

  final int x;
  final int y;

  static final Codec<Point> codec = _$pointCodec;
  factory Point.fromJson(Object? json) => codec.decode(json);
  Object? toJson() => codec.encode(this);
}

@Codable()
final class Collections {
  const Collections({
    required this.ints,
    required this.nullableStrings,
    required this.points,
    required this.scores,
    required this.maybePoints,
  });

  final List<int> ints;
  final List<String?> nullableStrings; // 可空元素 → 元素 .nullable()
  final List<Point> points; // 嵌套模型列表
  final Map<String, int> scores;
  final Map<String, Point?> maybePoints; // 可空嵌套值

  static final Codec<Collections> codec = _$collectionsCodec;
  factory Collections.fromJson(Object? json) => codec.decode(json);
  Object? toJson() => codec.encode(this);
}
