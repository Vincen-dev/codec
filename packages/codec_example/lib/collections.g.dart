// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collections.dart';

// **************************************************************************
// CodableGenerator
// **************************************************************************

final Codec<Point> _$pointCodec = Codec.object<Point>(
  (b) => Point(
    x: b.required<int>('x', Codec.integer),
    y: b.required<int>('y', Codec.integer),
  ),
  encode: (v) => {
    'x': Codec.integer.encode(v.x),
    'y': Codec.integer.encode(v.y),
  },
);

final Codec<Collections> _$collectionsCodec = Codec.object<Collections>(
  (b) => Collections(
    ints: b.required<List<int>>('ints', Codec.integer.list()),
    nullableStrings: b.required<List<String?>>('nullableStrings', Codec.string.nullable().list()),
    points: b.required<List<Point>>('points', Point.codec.list()),
    scores: b.required<Map<String, int>>('scores', Codec.mapOf(Codec.integer)),
    maybePoints: b.required<Map<String, Point?>>('maybePoints', Codec.mapOf(Point.codec.nullable())),
  ),
  encode: (v) => {
    'ints': Codec.integer.list().encode(v.ints),
    'nullableStrings': Codec.string.nullable().list().encode(v.nullableStrings),
    'points': Point.codec.list().encode(v.points),
    'scores': Codec.mapOf(Codec.integer).encode(v.scores),
    'maybePoints': Codec.mapOf(Point.codec.nullable()).encode(v.maybePoints),
  },
);
