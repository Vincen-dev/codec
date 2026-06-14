// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nested.dart';

// **************************************************************************
// CodableGenerator
// **************************************************************************

final Codec<Child> _$childCodec = Codec.object<Child>(
  (b) => Child(
    label: b.required<String>('label', Codec.string),
  ),
  encode: (v) => {
    'label': Codec.string.encode(v.label),
  },
);

final Codec<Parent> _$parentCodec = Codec.object<Parent>(
  (b) => Parent(
    child: b.required<Child>('child', Child.codec),
    code: b.required<String>('code', _shoutCodec),
  ),
  encode: (v) => {
    'child': Child.codec.encode(v.child),
    'code': _shoutCodec.encode(v.code),
  },
);

final Codec<Tree> _$treeCodec = Codec.object<Tree>(
  (b) => Tree(
    value: b.required<int>('value', Codec.integer),
    children: b.optionalOr<List<Tree>>('children', Codec.lazy(() => Tree.codec).list(), const []),
  ),
  encode: (v) => {
    'value': Codec.integer.encode(v.value),
    'children': Codec.lazy(() => Tree.codec).list().encode(v.children),
  },
);
