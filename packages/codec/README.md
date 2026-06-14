# codec

[![pub version](https://img.shields.io/pub/v/codec.svg)](https://pub.dev/packages/codec)
[![pub points](https://img.shields.io/pub/points/codec)](https://pub.dev/packages/codec/score)
[![likes](https://img.shields.io/pub/likes/codec)](https://pub.dev/packages/codec/score)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Type-safe, composable JSON codecs for Dart — path-precise errors, zero dependencies.**

`codec` models JSON encoding and decoding as composable, first-class `Codec<T>` objects. A decode
failure throws a structured `CodecException` whose message pinpoints the exact location
(`$.user.contacts[2].phone`) and the offending value — so malformed payloads are easy to diagnose,
bucket for monitoring, and assert against in tests.

## Features

- **Path-precise errors** — every failure reports `$.path[i].field`, the expected type, and the actual value.
- **Composable** — chain `.nullable()`, `.list()`, `.refine()`, `.bimap()`, `.withDefault()`, `.orElse()` on any `Codec<T>`.
- **One definition, both directions** — `decode` (fromJson) and `encode` (toJson) stay in sync, preventing drift.
- **Hard cases, first-class** — discriminated unions, recursion (`Codec.lazy`), multi-version compatibility (`Codec.firstOf`), and enum mapping with forward-compatible fallbacks.
- **Structured, configurable exceptions** — pattern-match `DecodeException.errors` / `kind` for monitoring and i18n, or opt into `FormatException` compatibility via `.withFormatExceptions()`.
- **Zero third-party dependencies** — pure Dart SDK.

## Installation

```yaml
dependencies:
  codec: ^0.2.1
```

Or run `dart pub add codec`. For annotation-driven code generation (`@Codable` → codec fields),
see the companion package [`codec_gen`](https://pub.dev/packages/codec_gen).

## Contents

- [Quick start](#quick-start)
- [When to use](#when-to-use--when-not-to-use)
- [API reference](#api-reference)
- [Cookbook](#cookbook)
- [Error modes](#error-modes)
- [Integration](#integrating-with-data-sources--interceptors)
- [Testing](#testing-template)
- [Security](#security-considerations)
- [Anti-patterns](#anti-patterns)
- [Performance](#performance)
- [FAQ](#faq)

---

## Quick start

```dart
import 'package:codec/codec.dart';

final class UserModel {
  final String name;
  final String? avatar;
  final int age;
  const UserModel({required this.name, this.avatar, required this.age});

  static final Codec<UserModel> codec = Codec.object<UserModel>(
    (b) => UserModel(
      name: b.required('name', Codec.string),
      avatar: b.optional('avatar', Codec.string),
      age: b.optionalOr('age', Codec.integer, 0),
    ),
    encode: (u) => {
      'name': u.name,
      'avatar': u.avatar,
      'age': u.age,
    }.omitNulls,
  );

  factory UserModel.fromJson(Object? json) =>
      codec.decode(json, typeHint: 'UserModel');

  Object? toJson() => codec.encode(this);
}
```

Example error output (`DecodeException`, message includes full path):
```
decode UserModel failed (1 error):
  - $.contacts[2].avatar: expected String, got: 1 (int)
```

---

## When to use / when not to use

**Use codec when you need:**
- Complex nested structures where path-precise errors matter
- Discriminated unions, multi-version field compatibility, or recursive structures
- Both `fromJson` and `toJson` in sync, preventing drift
- Structured exceptions for monitoring bucketing, i18n, or stable test assertions

**Skip codec when:**
- Your DTO has only 1–2 fields and `@JsonSerializable()` + build_runner already serves
  you well
- You are already using `freezed` — there is no need to replace it

> **Avoid running two serialization systems in parallel.** Route new models through
> codec and let existing models evolve naturally. A bulk rewrite for consistency is
> not worthwhile.

---

## API reference

### Primitives (const, reusable)

| Codec | Accepted input | Notes |
|---|---|---|
| `Codec.string` | `String` | — |
| `Codec.integer` | `int` / whole-number float (`1.0`) / `String` (no decimal point) | **Rejects** true decimals (`1.5`) and NaN/Infinity to prevent silent truncation |
| `Codec.number` | `int` / `double` / `String` → `double` | Encode **rejects** NaN/±Infinity (throws `EncodeException`) |
| `Codec.numeric` | `num` / `String` | Encode rejects NaN/±Infinity for double subtypes |
| `Codec.boolean` | `bool` / `num` (non-zero = true) / `"true"/"false"/"yes"/"no"/"1"/"0"` | Tolerates common backend variants; any non-zero number is `true` |
| `Codec.dateTime` | ISO-8601 string / epoch ms (`int` or `double`) | Encode outputs ISO-8601, preserving the original timezone |
| `Codec.dateTimeUtc` | Same as `dateTime` | Encode calls `toUtc()` before outputting ISO-8601 |
| `Codec.dateTimeSeconds` | ISO-8601 string / epoch **seconds** | Encode outputs ISO-8601 (asymmetric decode/encode) |
| `Codec.dateTimeMillisUtc` | Epoch millisecond number only (`int` / `double`) | Encode returns a **millisecond number**; decode produces `isUtc=true`; **symmetric** |
| `Codec.dateTimeSecondsUtc` | Epoch **second** number only | Encode returns a **second number**; sub-second precision is truncated |
| `Codec.any` | Anything | Passes `Object?` through unchanged |
| `Codec.trimmedString` | `String` → trimmed | — |
| `Codec.nonEmptyString` | Non-empty after trim | Failure gives `FailedRefinement` |

### Chainable combinators (available on any `Codec<T>`)

| Method | Effect |
|---|---|
| `.nullable()` | `Codec<T?>`: passes `null` through unchanged |
| `.withDefault(v)` | Falls back to `v` **on null only** — not on type or format errors, keeping schema drift visible |
| `.refine(predicate, msg)` | Asserts a condition after decoding |
| `.bimap(forward, reverse)` | Bidirectional transform to/from a domain type |
| `.list()` | `Codec<List<T>>` |
| `.orElse(other)` | On failure, tries `other` |
| `.withFormatExceptions()` | Wraps `CodecException` as `FormatException` for compatibility with existing `on FormatException` handlers; **must be the outermost call in the chain** |

### Top-level factories

| Method | Use for |
|---|---|
| `Codec.object(decode, encode:)` | Plain objects |
| `Codec.discriminated(tag:, cases:, encode:)` | Sealed union types |
| `Codec.lazy(() => ...)` | Recursive structures |
| `Codec.firstOf([...])` | Multi-version compatibility |
| `Codec.mapOf(value)` | `Map<String, V>` |
| `Codec.enumByName({...}, unknownFallback:)` | String → enum with an optional forward-compatible fallback |
| `Codec.enumOf(valueCodec, {...}, unknownFallback:)` | Arbitrary value (e.g. int code) → enum with an optional forward-compatible fallback |
| `Codec.custom(decode:, encode:)` | Fully custom codec |

### Exit points

| Method | Returns | Failure behavior |
|---|---|---|
| `codec.decode(json, mode:, typeHint:)` | `T` | Throws `DecodeException` by default; the message includes the path and reason. Throws `FormatException` when `.withFormatExceptions()` is used. |
| `codec.encode(value)` | `Object?` | Throws `EncodeException` by default (covers a missing encode closure, a `bimap` reverse throw, etc.). Throws `FormatException` when `.withFormatExceptions()` is used. |

---

## Cookbook

### 1. Nested objects

```dart
final addressCodec = Codec.object<Address>(
  (b) => Address(
    city: b.required('city', Codec.string),
    zip: b.required('zip', Codec.string),
  ),
  encode: (a) => {'city': a.city, 'zip': a.zip},
);

final userCodec = Codec.object<User>(
  (b) => User(
    name: b.required('name', Codec.string),
    address: b.required('address', addressCodec),  // pass codec directly
  ),
  encode: (u) => {'name': u.name, 'address': addressCodec.encode(u.address)},
);
```

### 2. List with index in error path

```dart
final ordersCodec = Codec.object<Order>(
  (b) => Order(
    items: b.required('items', itemCodec.list()),
    tags: b.optionalOr('tags', Codec.string.list(), const []),
  ),
);
// Errors are reported as $.items[3].sku automatically
```

### 3. Discriminated union (sealed class)

```dart
sealed class RefundEvent {}
final class CreatedEvent extends RefundEvent {
  CreatedEvent({required this.at, required this.operator});
  final DateTime at;
  final String operator;
}
final class ApprovedEvent extends RefundEvent {
  ApprovedEvent({required this.at, required this.approver});
  final DateTime at;
  final String approver;
}

final eventCodec = Codec.discriminated<RefundEvent>(
  tag: 'type',
  cases: {
    'created': Codec.object<RefundEvent>(
      (b) => CreatedEvent(
        at: b.required('at', Codec.dateTime),
        operator: b.required('operator', Codec.string),
      ),
    ),
    'approved': Codec.object<RefundEvent>(
      (b) => ApprovedEvent(
        at: b.required('at', Codec.dateTime),
        approver: b.required('approver', Codec.string),
      ),
    ),
  },
  encode: (e) => switch (e) {
    CreatedEvent(:final at, :final operator) =>
      ('created', {'at': at.toIso8601String(), 'operator': operator}),
    ApprovedEvent(:final at, :final approver) =>
      ('approved', {'at': at.toIso8601String(), 'approver': approver}),
  },
);
```

> A `sealed class` with a `switch` expression lets the compiler flag a missing case
> the moment you add a new subtype — forgotten encode branches become compile errors,
> not runtime surprises.

### 4. Recursive structures (comment trees, menus)

```dart
late final Codec<Comment> commentCodec;
commentCodec = Codec.object<Comment>(
  (b) => Comment(
    id: b.required('id', Codec.string),
    text: b.required('text', Codec.string),
    replies: b.optionalOr(
      'replies',
      Codec.lazy(() => commentCodec).list(),
      const [],
    ),
  ),
  encode: (c) => {
    'id': c.id,
    'text': c.text,
    'replies': c.replies.map(commentCodec.encode).toList(),
  },
);
```

### 5. Multi-version compatibility (v1 string id, v2 int id)

```dart
final idCodec = Codec.firstOf<int>([
  Codec.integer,
  Codec.string.bimap(int.parse, (i) => '$i'),
]);
```

### 6. Enum mapping

```dart
enum RefundStatus { pending, success, rejected }

final statusCodec = Codec.enumByName<RefundStatus>(
  const {
    'PENDING': RefundStatus.pending,
    'SUCCESS': RefundStatus.success,
    'REJECTED': RefundStatus.rejected,
  },
  toJson: (s) => switch (s) {
    RefundStatus.pending  => 'PENDING',
    RefundStatus.success  => 'SUCCESS',
    RefundStatus.rejected => 'REJECTED',
  },
);
```

> Avoid `RefundStatus.values.byName(s)` — it throws immediately when the backend uses
> different casing or underscores, and offers no fallback. An explicit map is the
> correct approach.

For forward compatibility with backends that may introduce new enum values, pass
`unknownFallback`. Values that successfully decode but are absent from the mapping fall
back to the specified enum instead of throwing `UnknownTag`. **Type and format errors
still surface normally** — an int field receiving a non-numeric string is never
silently swallowed:

```dart
enum StoreArea { hk, jp, au }

final areaCodec = Codec.enumOf<StoreArea, int>(
  Codec.integer,
  const {84: StoreArea.hk, 99: StoreArea.jp, 12: StoreArea.au},
  unknownFallback: StoreArea.hk,   // unknown / new code -> hk; record still decodes
);

areaCodec.decode(99);   // StoreArea.jp  (exact match)
areaCodec.decode(176);  // StoreArea.hk  (unknown code, fallback applied)
areaCodec.decode('x');  // throws DecodeException (int decode failed; type error is not swallowed)
```

> Without `unknownFallback`, strict mode is preserved: unknown values throw `UnknownTag`
> listing the valid set, so protocol schema drift is surfaced rather than silently
> ignored.

### 7. Field-level validation (refine)

```dart
final priceCodec = Codec.number.refine((p) => p >= 0, 'price must be >= 0');
final emailCodec = Codec.string.refine(
  (s) => s.contains('@'),
  'invalid email',
);
```

### 8. Field-rename compatibility

```dart
// Backend v1 used user_name; v2 renamed it to name
final c = Codec.object<User>(
  (b) => User(
    name: b.optional('name', Codec.string)
       ?? b.required('user_name', Codec.string),
  ),
);
```

---

## Error modes

### `failFast` (default)

Stops at the first error. Appropriate for **API response deserialization** — if one
field is corrupt, the business logic cannot proceed regardless.

### `accumulate`

List, map, and `firstOf` sibling branches **continue past failures**, collecting all
errors into a single exception. Use this for:
- Bulk import validation ("100 CSV rows — report all 7 broken ones")
- Multi-version data structure auditing

```dart
final result = codec.decode(json, mode: ErrorMode.accumulate);
```

> **The object builder is always fail-fast internally.** When one field fails, the
> builder short-circuits to prevent subsequent chained calls (`.trim()`,
> `.toUpperCase()`, etc.) from receiving a null and throwing. This is an inherent
> constraint of the imperative builder style.

---

## Integrating with data sources / interceptors

`decode` throws `DecodeException` (a sealed subclass of `CodecException`) by default;
`encode` throws `EncodeException`. Choose one of two approaches:

**Structured handling** (recommended) — catch `DecodeException` directly:

```dart
// inside a data source
final raw = await dio.post<dynamic>(path, data: ...);
try {
  return MyResponseModel.codec.decode(
    raw.data,
    typeHint: 'MyResponseModel',  // improves readability of error messages
  );
} on DecodeException catch (e, st) {
  // e.errors is a list of path-annotated failures;
  // e.isAllMissing / e.hasWrongType are useful for monitoring bucketing
  throw JsonException(message: e.message, cause: e, stackTrace: st);
}
```

**Compatibility mode** — when changing existing `on FormatException` handlers is
impractical, append `.withFormatExceptions()` to the outermost codec at definition
time:

```dart
// at definition time:
static final Codec<MyResponseModel> codec =
    _buildCodec().withFormatExceptions();

// existing call sites are unchanged:
} on FormatException catch (e, st) {
  throw JsonException(message: e.message, cause: e, stackTrace: st);
}
```

codegen users can set `exception_style: format` in `build.yaml` to have all generated
codecs append `.withFormatExceptions()` automatically (see the codec_gen README).

---

## Testing template

Cover at least four categories for each codec:

```dart
test('normal decode', () {
  final r = userCodec.decode({'name': 'A', 'age': 30});
  expect(r.name, 'A');
});

test('missing required field reports exact path', () {
  expect(
    () => userCodec.decode({}),
    throwsA(
      isA<DecodeException>().having(
        (e) => e.message, 'message',
        allOf(contains(r'$.name'), contains('missing required')),
      ),
    ),
  );
});

test('type mismatch reports WrongType', () {
  expect(
    () => userCodec.decode({'name': 123}),
    throwsA(isA<DecodeException>().having(
      (e) => e.message, 'message',
      contains('expected String'),
    )),
  );
});

test('encode round-trips correctly', () {
  const u = UserModel(name: 'A', age: 1);
  final json = userCodec.encode(u);
  expect(userCodec.decode(json).name, 'A');
});
```

> For List/Map decoding, add a group that passes `mode: ErrorMode.accumulate` to
> confirm that **all** errors are collected, not just the first.

---

## Security considerations

### Decode depth / DoS

Recursive decoding (`Codec.lazy`, nested `object`, `.list()`, `mapOf`) has no built-in
depth limit; deeply nested untrusted input can trigger a stack overflow. In practice,
the upstream `dart:convert jsonDecode` call usually hits the limit first. When accepting
untrusted data, enforce payload size and nesting depth limits at the ingestion layer.

### Error message leakage

`DecodeException.message` / `toString()` embeds a truncated excerpt of the failing
value (up to 80 characters) and its `runtimeType`. **Do not** log the raw message for
sensitive payloads; construct sanitized messages from the structured `errors` / `kind`
fields instead.

---

## Anti-patterns

### Using `??` to silently swallow decode failures as defaults

```dart
// bad: a missing 'name' silently becomes an empty string; callers have no idea
name: b.optional('name', Codec.string) ?? '',
```

```dart
// good: required fields produce an explicit, path-annotated error
name: b.required('name', Codec.string),
```

### Defining the codec inside `fromJson`

```dart
// bad: allocates a new Codec instance on every fromJson call
factory UserModel.fromJson(Object? json) {
  final codec = Codec.object<UserModel>(...);  // re-allocated every call
  return codec.decode(json);
}
```

```dart
// good: static final — one instance for the lifetime of the process
static final Codec<UserModel> codec = Codec.object<UserModel>(...);
factory UserModel.fromJson(Object? json) => codec.decode(json);
```

### Missing encode branch in a discriminated union

```dart
// bad: _Cancelled was added but the encode switch was not updated — fails at runtime
encode: (e) => switch (e) {
  _Created() => ...,
  _Approved() => ...,
  // _Cancelled omitted — compiler does not catch this
},
```

```dart
// good: sealed class + switch expression; exhaustiveness is enforced at compile time
sealed class RefundEvent {}
encode: (e) => switch (e) {
  _Created()   => ...,
  _Approved()  => ...,
  _Cancelled() => ...,  // omitting this is a compile error
},
```

### Decoding list elements outside the builder

```dart
// bad: error path is lost — impossible to identify which element failed
items: (json['items'] as List).map(ItemModel.fromJson).toList(),
```

```dart
// good: the builder appends [i] to the path automatically
items: b.required('items', ItemModel.codec.list()),
```

---

## Performance

- Primitive codecs are `const` singletons — zero allocation per call
- Paths use an immutable linked list — deep nesting avoids O(n^2) string concatenation
- The failure path returns a value type (`DecodeOutcome`) rather than throwing — no
  stack-unwind overhead on the hot path
- List decoding of 1 M elements runs **2-3x faster** than the naive "extension function
  + exception + string path concatenation" approach

For recursive codecs, always use `Codec.lazy` and **declare the outer codec as
`late final`**:

```dart
// bad: no late — compiler error "cannot reference an undeclared variable"
final commentCodec = Codec.object((b) => ...
  Codec.lazy(() => commentCodec)  // commentCodec not yet assigned
);

// good: late final + two-step assignment
late final Codec<Comment> commentCodec;
commentCodec = Codec.object((b) => ...
  Codec.lazy(() => commentCodec)
);
```

---

## FAQ

**Q: Why not just use freezed + json_serializable?**
A: They can coexist, but codec has a clear advantage in three scenarios:
1. Discriminated unions — freezed's `fromJson` requires manual factory branches
2. Multi-version field compatibility — difficult to express with annotation-based codegen
3. Path-precise errors — `CheckedFromJsonException` does not surface nested field paths

**Q: Does `accumulate` mode work at the individual-field level inside an object?**
A: No. Combining an imperative builder with `accumulate` would allow one field's failure
to propagate `null` into subsequent chained calls, causing NPEs. The Validation
Applicative style can solve this, but it requires a declarative DSL that Dart's type
inference cannot support — the ergonomic cost for 99% of use cases would be
unacceptable. `accumulate` applies between sibling elements in lists, maps, and
`firstOf` only; the object builder is always fail-fast.

**Q: Can codec coexist with `@JsonSerializable()`?**
A: Yes. Inside a `Codec.object` decode closure you can call `OldModel.fromJson`
directly, and in the encode closure call `OldModel.toJson()` — wrapping the legacy model
as a first-class codec. Migration can be fully incremental.

---

[MIT](LICENSE) © Vincen (Zhang Wenjin)
