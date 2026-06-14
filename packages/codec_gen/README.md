# codec_gen

[![pub version](https://img.shields.io/pub/v/codec_gen.svg)](https://pub.dev/packages/codec_gen)
[![pub points](https://img.shields.io/pub/points/codec_gen)](https://pub.dev/packages/codec_gen/score)
[![likes](https://img.shields.io/pub/likes/codec_gen)](https://pub.dev/packages/codec_gen/score)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Annotation-driven build_runner code generator for the [`codec`](https://pub.dev/packages/codec) runtime package.**

Annotate your model with `@Codable` or `@CodecEnum` and run `build_runner`; `codec_gen` emits
a `_$xxxCodec` static field wired to a fully type-safe `Codec<T>` — no hand-written
encode/decode boilerplate required.

## Features

- **Annotation-driven codegen** — `@Codable` on a class generates a complete `Codec<T>` with both `decode` and `encode` paths.
- **Rich field control** — `@CodecField` covers renaming, default values, null inclusion, custom codecs, `DateTime` modes, and enum value mapping.
- **Build-time validation** — schema errors (unrecognised field types, missing `@Codable` on nested models, partial enum coverage, mismatched `unknownEnumValue`) surface during `build_runner`, not at runtime.
- **Configurable exception style** — set `exception_style: format` in `build.yaml` to make generated codecs throw `FormatException` instead of `DecodeException`, enabling zero-touch migration of existing error handlers.
- **Plays well with others** — uses `SharedPartBuilder` so it coexists with `json_serializable`, `freezed`, and any other part-file generator in the same build.

## Installation

```yaml
dependencies:
  codec: ^0.2.1

dev_dependencies:
  codec_gen: ^0.2.0
  build_runner: ^2.4.0
```

Or via the command line:

```bash
dart pub add codec
dart pub add dev:codec_gen dev:build_runner
```

## Contents

- [Annotate your model](#annotate-your-model)
- [Field annotation quick reference](#field-annotation-quick-reference)
- [Build options](#build-options-buildyaml)
- [Codegen-time validation](#codegen-time-validation)
- [Field rename rules](#field-rename-rules-fieldrename)

---

## Annotate your model

```dart
import 'package:codec/codec.dart';
part 'order_model.g.dart';

@Codable(includeIfNull: false)
final class OrderModel {
  final int orderId;

  @CodecField(name: 'total_amount', defaultValue: 0.0)
  final double totalAmount;

  const OrderModel({required this.orderId, required this.totalAmount});

  static final Codec<OrderModel> codec = _$orderModelCodec;
  factory OrderModel.fromJson(Object? json) => codec.decode(json);
  Object? toJson() => codec.encode(this);
}
```

Run the generator:

```bash
dart run build_runner build --delete-conflicting-outputs
```

For full annotation semantics, see the dartdoc in `annotations.dart` inside the
[`codec`](https://pub.dev/packages/codec) package.

---

## Field annotation quick reference

```dart
@Codable(includeIfNull: false)              // class-level: omit null fields in toJson by default
final class OrderModel {
  // Plain field — no annotation; uses the Dart field name as the JSON key
  final String orderId;

  // Rename + default value
  @CodecField(name: 'total_amount', defaultValue: 0.0)
  final double totalAmount;

  // Field-level override of class-level includeIfNull: keep null
  @CodecField(includeIfNull: true)
  final String? note;

  // Skip this field (two equivalent forms)
  @CodecIgnore()
  final String? _localCache;
  // or: @CodecField(ignore: true)

  // Custom codec
  @CodecField(codec: '_amountCodec')
  final Decimal price;

  // DateTime modes (no string reference needed)
  @CodecField(dateTime: DateTimeMode.utc)
  final DateTime createdAt;            // uses Codec.dateTimeUtc
  @CodecField(dateTime: DateTimeMode.seconds)
  final DateTime serverTime;           // uses Codec.dateTimeSeconds

  // Millisecond timestamp + UTC DateTime (time-zone-aware)
  @CodecField(dateTime: DateTimeMode.millisUtc)
  final DateTime txTime;               // decodes to isUtc=true; encodes back to ms integer
  @CodecField(dateTime: DateTimeMode.secondsUtc)
  final DateTime expireAt;             // same but second granularity

  // Enum mapped by a named property value (enum needs no @CodecEnum, keeping core/domain clean)
  @CodecField(enumValueField: 'code')
  final OrderState orderState;         // JSON {"orderState": 3} <-> instance whose code == 3

  // Forward-compatible unknown code: fall back to a specific enum value instead of throwing
  @CodecField(enumValueField: 'code', unknownEnumValue: StoreArea.hk)
  final StoreArea regionId;            // unrecognised / new backend code -> hk

  // const List/Map default values
  @CodecField(defaultValue: <String>[])
  final List<String> tags;
  @CodecField(defaultValue: <String, int>{})
  final Map<String, int> counters;
}
```

---

## Build options (`build.yaml`)

### `exception_style`

Controls the exception type thrown by the generated top-level codec (default: `codec`):

```yaml
targets:
  $default:
    builders:
      codec_gen:
        options:
          exception_style: format   # throw FormatException; default codec throws DecodeException
```

| Value | Behaviour |
|---|---|
| `codec` (default) | The generated `_$xxxCodec` is used directly; `decode` / `encode` throw `DecodeException` / `EncodeException` |
| `format` | The generated `_$xxxCodec` automatically has `.withFormatExceptions()` appended; `decode` / `encode` throw Dart's built-in `FormatException` |

Use `exception_style: format` to provide a zero-touch migration path for existing code that
catches `on FormatException` — no changes required at call sites. When structured error
handling is needed, use the default `codec` mode and catch `on DecodeException` /
`on EncodeException` to inspect the `errors`, `cause`, and `$.path` location fields.

### `field_rename`

Sets a project-wide default field-rename strategy, applied to every `@Codable`
class that does not specify its own `fieldRename` (default: none):

```yaml
targets:
  $default:
    builders:
      codec_gen:
        options:
          field_rename: snake   # default for all @Codable classes
```

Allowed values are the `FieldRename` enum names: `none`, `snake`, `kebab`,
`pascal`, `camel`, `screamingSnake`. An unknown value fails the build with an
`ArgumentError`.

Precedence (highest first):

| Source | Wins when |
|---|---|
| `@CodecField(name: 'x')` | a field sets an explicit JSON name |
| `@Codable(fieldRename: X)` | the class explicitly sets a strategy (including `FieldRename.none` to opt back out of a global default) |
| `field_rename` (build.yaml) | the class does not specify `fieldRename` |
| `FieldRename.none` | nothing above applies |

---

## Codegen-time validation

The following errors are reported during `build_runner` and will never be deferred to runtime:

- `@Codable` not applied to a class, or the class has no unnamed constructor.
- A field type is not recognised by `codec_gen` (hint: use `@CodecField(codec: 'xxx')` as an escape hatch).
- A nested model type does not carry `@Codable` (hint: add `@Codable()` or supply a field-level codec).
- A `Map` key type is not `String`.
- Mixed `String` / `int` `@CodecValue` types within the same enum.
- `@CodecField(enumValueField:)` applied to a non-enum field, or the enum has no such property, or the target property type is not `int` / `String` / `double` / `num`.
- `@CodecField(unknownEnumValue:)` set without `enumValueField`, or its enum type does not match the field's enum type (the former is a misuse; the latter would generate non-compiling code).
- `@CodecEnum` with only partial `@CodecValue` coverage: all values must be annotated or none (defaulting to `.name` / `valueField`), to prevent a runtime `EncodeException` on unannotated values.

---

## Field rename rules (`fieldRename`)

Set per class with `@Codable(fieldRename: FieldRename.snake)`, or project-wide
with the `field_rename` build option above. `@Codable(fieldRename: ...)` overrides
the project default; omit it to inherit. All strategies use the same
word-splitting rules as Lodash / inflection:

| Dart field | snake | kebab | pascal | screamingSnake |
|---|---|---|---|---|
| `userName` | `user_name` | `user-name` | `UserName` | `USER_NAME` |
| `userID` | `user_id` | `user-id` | `UserId` | `USER_ID` |
| `URLPath` | `url_path` | `url-path` | `UrlPath` | `URL_PATH` |
| `userIDValue` | `user_id_value` | `user-id-value` | `UserIdValue` | `USER_ID_VALUE` |
| `parseHTTPURLPath` | `parse_httpurl_path` | `parse-httpurl-path` | `ParseHttpurlPath` | `PARSE_HTTPURL_PATH` |

> A purely consecutive-uppercase run with no embedded lowercase (e.g. `HTTPURL`) cannot be
> split into `HTTP` + `URL` from the string alone and is treated as a single word. If the
> backend uses word-separated field names, keep explicit word boundaries in the Dart field
> name (e.g. `parseHttpUrlPath`) or use `@CodecField(name: '...')` to specify the JSON key
> explicitly.

---

[MIT](LICENSE) © Vincen (Zhang Wenjin)
