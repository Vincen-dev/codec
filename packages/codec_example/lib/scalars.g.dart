// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scalars.dart';

// **************************************************************************
// CodableGenerator
// **************************************************************************

final Codec<Primitives> _$primitivesCodec = (() {
  final n0 = Codec.any.nullable();
  return Codec.object<Primitives>(
    (b) => Primitives(
      s: b.required<String>('s', Codec.string),
      i: b.required<int>('i', Codec.integer),
      d: b.required<double>('d', Codec.number),
      n: b.required<num>('n', Codec.numeric),
      b: b.required<bool>('b', Codec.boolean),
      any: b.optional<Object?>('any', Codec.any),
    ),
    encode: (v) => {
      's': Codec.string.encode(v.s),
      'i': Codec.integer.encode(v.i),
      'd': Codec.number.encode(v.d),
      'n': Codec.numeric.encode(v.n),
      'b': Codec.boolean.encode(v.b),
      'any': n0.encode(v.any),
    },
  );
})();

final Codec<Times> _$timesCodec = Codec.object<Times>(
  (b) => Times(
    local: b.required<DateTime>('local', Codec.dateTime),
    utc: b.required<DateTime>('utc', Codec.dateTimeUtc),
    seconds: b.required<DateTime>('seconds', Codec.dateTimeSeconds),
    millisUtc: b.required<DateTime>('millisUtc', Codec.dateTimeMillisUtc),
    secondsUtc: b.required<DateTime>('secondsUtc', Codec.dateTimeSecondsUtc),
  ),
  encode: (v) => {
    'local': Codec.dateTime.encode(v.local),
    'utc': Codec.dateTimeUtc.encode(v.utc),
    'seconds': Codec.dateTimeSeconds.encode(v.seconds),
    'millisUtc': Codec.dateTimeMillisUtc.encode(v.millisUtc),
    'secondsUtc': Codec.dateTimeSecondsUtc.encode(v.secondsUtc),
  },
);

final Codec<Account> _$accountCodec = Codec.object<Account>(
  (b) => Account(
    accountId: b.required<String>('account_id', Codec.string),
    displayName: b.optional<String>('name', Codec.string),
    loginCount: b.optionalOr<int>('login_count', Codec.integer, 0),
  ),
  encode: (v) => {
    'account_id': Codec.string.encode(v.accountId),
    if (v.displayName != null) 'name': Codec.string.encode(v.displayName!),
    'login_count': Codec.integer.encode(v.loginCount),
  },
);
