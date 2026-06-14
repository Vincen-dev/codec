# Changelog

## 0.2.1

- Docs & metadata: English `description` and CHANGELOG; `repository` now points to the package subdirectory (pub.dev scoring). No code changes.

## 0.2.0

### Breaking changes

- **`CodecException` no longer extends `FormatException`**: `decode` / `encode` now throw
  their own types `DecodeException` / `EncodeException` (both sealed subclasses of
  `CodecException`) instead of the Dart built-in `FormatException`. **Migration**:
  - **codegen users**: set `exception_style: format` on the `codec_gen` builder in
    `build.yaml`; the generated top-level codec will automatically append
    `.withFormatExceptions()`, preserving the old behavior.
  - **hand-written codecs**: call `.withFormatExceptions()` on the outermost codec to
    wrap all `CodecException` throws as `FormatException`.
  - **structured error handling**: switch to `on DecodeException` / `on EncodeException`
    and use `errors` / `isAllMissing` / `hasWrongType` (decode) or `cause` /
    `causeStackTrace` (encode) to inspect details.

### Added

- **`Codec.withFormatExceptions()` combinator**: attach to the outermost codec to make
  `decode` / `encode` wrap all `CodecException` throws as Dart's built-in
  `FormatException` — a zero-migration compatibility shim for existing
  `on FormatException` handlers. **Must be the last call in the chain** (applies to the
  entire codec chain).
- **`UnexpectedError` error kind**: a top-level catch-all that captures any
  non-`CodecException` thrown unexpectedly inside `decode` / `encode`, converging it
  into a `DecodeException` to keep the exception model airtight.

### Fixes (robustness)

- **DateTime codecs no longer leak underlying exceptions**: NaN / ±Infinity / out-of-range
  epoch numbers (`UnsupportedError` / `RangeError`) are now caught and converted to
  `BadFormat`, thrown as a `DecodeException`.
- **`refine` predicate throws + top-level unexpected exceptions are now unified**:
  arbitrary exceptions thrown inside a `refine` predicate, and unexpected exceptions that
  escape `decode` / `encode`, are all converged into `DecodeException` — decode / encode
  are now airtight and only throw `CodecException` (or `FormatException` in compat mode).

### Tests

- Runtime test count: 87 → 114 (new exception hierarchy, DateTime edge cases, refine
  robustness, and related coverage).

## 0.1.6

### Added (unknown-value forward compatibility)

- **`Codec.enumOf` / `Codec.enumByName` now accept an optional `unknownFallback`**:
  when decoding encounters an unknown tag (no mapping hit), fall back to the specified
  enum value instead of throwing `UnknownTag`. Default `null` = retain the original
  strict behavior, **fully backwards-compatible**. Typical use case: the backend may add
  or rename enum codes; the client needs forward compatibility so a single unknown value
  does not cause the entire record to fail decoding.
- **`CodecField.unknownEnumValue`** (annotation layer): used alongside `enumValueField`
  to declare the fallback enum value for unknown codes; codec_gen passes it through to
  the generated `Codec.enumOf(..., unknownFallback:)`. See codec_gen 0.1.6 for the
  codegen implementation.

### Design trade-off (preserving "no silent schema-drift swallowing")

- `unknownFallback` only catches "value decoded successfully but tag not in mapping";
  **type / format errors in the inner `valueCodec` still bubble normally** (e.g., an int
  field receiving a non-numeric string) and are not swallowed by the fallback. This
  mirrors `withDefault` (null-only fallback): the deliberate distinction between "unknown
  enum item" (business-level forward compat) and "wrong protocol shape" (must be exposed)
  is intentional.

### Tests

- 3 new cases: `enumOf` / `enumByName` unknown-value fallback; `unknownFallback` does
  not swallow inner type errors. Runtime test count: 84 → 87.

### Version

- Runtime package code changed (added `unknownFallback` / `unknownEnumValue`); `version`
  bumped 0.1.5 → 0.1.6, aligned with CHANGELOG.

## 0.1.5

### Added (annotation layer)

- **`CodecField.enumValueField`**: map an enum field by the value of one of the enum
  instance's own fields (e.g. `code`) instead of the enum name, **without requiring
  `@CodecEnum` on the enum itself**. Suitable for enums in a core / domain layer that
  should not depend on the serialization framework (no import or part file needed). Only
  valid on enum fields; the target field type must be `int` / `String` / `double` / `num`;
  mutually exclusive with `dateTime`; when set alongside `codec`, `codec` takes
  precedence. See codec_gen 0.1.5 for the codegen implementation.

### Historical debt (cleanup)

- `pubspec.yaml` `version` had been stuck at `0.1.0` while the CHANGELOG had progressed
  to `0.1.4` — a drift first noted in the codec_gen 0.1.4 "historical debt" entry.
  Since this release touches runtime code (adds `enumValueField`), the version has been
  bumped to `0.1.5` to realign with the CHANGELOG.

## 0.1.4

### Build / workspace

- **Joined pub workspace**: the root `pubspec.yaml` lists this package under `workspace:`;
  this package's `pubspec.yaml` adds `resolution: workspace`. Result: this package no
  longer generates its own `.dart_tool/package_config.json`; dependency resolution is
  handled by the root. The IDE's analyzer view from the project root can now resolve
  `package:test/test.dart` (previously `test` / `expect` were red in sub-package test
  files because the root used `flutter_test` instead of `test`).
- **SDK constraint raised**: `^3.4.0` → `^3.6.0` (minimum required for pub workspace).
- **`lints` downgraded to `^4.0.0`**: workspace shares a single dependency resolution,
  so this package must be compatible with the root's `flutter_lints ^4.0.0` (which
  transitively requires `lints ^4.0.0`). All lint rules used by this package are fully
  covered by lints 4.x; no functionality lost.
- **`.gitignore` extended with `build/`**: running `flutter test` in the sub-package
  produces hundreds of unit_test assets and native_assets; these are excluded from the
  repository.

## 0.1.3

### Added

- **`Codec.dateTimeMillisUtc`**: a **symmetric** codec between epoch-millisecond numbers
  and UTC `DateTime`. Decode accepts only numbers and returns a `DateTime` with
  `isUtc=true`, preventing device-timezone contamination when accessing `.year` / `.day`
  etc.; encode returns a millisecond integer (not an ISO string), matching the common
  pattern where both sides of a backend protocol use millisecond timestamps.
- **`Codec.dateTimeSecondsUtc`**: same as above but at second granularity. Encode uses
  integer truncation (consistent with the Unix `time(0)` convention); sub-second
  precision is discarded by the second-granularity protocol.
- **`DateTimeMode.millisUtc` / `DateTimeMode.secondsUtc`**: new enum values on the
  codec_gen side; select them with `@CodecField(dateTime: DateTimeMode.millisUtc)`.

### Tests

- 10 new cases: UTC `isUtc` flag, number round-trip, ISO string rejection, NaN/Infinity
  rejection, sub-second truncation, both local and UTC DateTime produce absolute
  milliseconds on encode.

## 0.1.2

### Added (annotation layer)

- **`FieldRename.screamingSnake`**: `userName` → `USER_NAME`.
- **`DateTimeMode` enum** + `CodecField.dateTime` field: lets codec_gen switch to
  `Codec.dateTimeUtc` / `Codec.dateTimeSeconds` without string references.
- **`CodecIgnore` annotation**: `@CodecIgnore()` is equivalent to
  `@CodecField(ignore: true)`.

### Docs

- `CodecField.includeIfNull` dartdoc updated from "field-level override not yet
  implemented" to the formal semantic description (implemented in codec_gen 0.1.2).
- `CodecField.defaultValue` dartdoc explicitly documents support for const List /
  const Map.

## 0.1.1

### Behavior changes (fix potential silent data corruption)

- `Codec.integer` now rejects true decimals (`1.5`) and NaN/±Infinity; it only accepts
  whole-number floats (`1.0`) and integer strings with no decimal point. The previous
  silent `toInt()` truncation could silently discard the fractional part; it now throws
  `BadFormat` explicitly.
- `Codec.number` / `Codec.numeric` throw `EncodeException` when encoding NaN/±Infinity,
  pulling the error into the codec error model and preventing `JsonUnsupportedObjectError`
  from surfacing only at the outer `jsonEncode` call.
- `Codec.discriminated` encode: if the `encode` closure's returned body accidentally
  contains a key with the same name as the discriminator field, the codec-injected tag
  always wins (map literal spread order changed from `{tag, ...body}` to `{...body, tag}`).

### Added

- `Codec.dateTimeUtc`: encodes by calling `toUtc().toIso8601String()`, producing
  semantically consistent output regardless of the local timezone.
- `Codec.dateTimeSeconds`: interprets epoch numbers as Unix **seconds**, avoiding the
  existing `dateTime` codec accidentally treating them as milliseconds (which would parse
  to a date near 1970).
- `Codec.dateTime` itself: epoch numbers now accept `num` (previously only `int`),
  allowing JS-serialized values like `1700000000000.0` (integer milliseconds with a
  decimal point).

### Doc enhancements

- `Codec.withDefault` / `FieldsReader.optionalOr` now explicitly document "null-only
  fallback" to avoid confusion with "fallback on any failure"; use `Codec.firstOf` to
  express the latter explicitly.

### Tests

- 15 new edge-case tests covering the above changes: `integer` strict integer-float vs
  true-decimal distinction; `number`/`numeric` encode non-finite; `discriminated` tag
  override prevention; `dateTime` multi-form epoch input. Total tests: 58 → 73.

## 0.1.0

- First independent release: extracted from internal codebase as a standalone pub package.
- Public API: `Codec<T>` abstract class + static factories (`string` / `object` /
  `discriminated` / `lazy` / `firstOf` / `enumByName` / `mapOf` / `custom`, etc.) +
  chainable combinators (`nullable` / `withDefault` / `refine` / `bimap` / `list` /
  `orElse`) + `MapOmitNulls` extension.
- On failure, throws Dart SDK built-in `FormatException`; message includes
  `$.path[idx].field` location and supports `ErrorMode.failFast` /
  `ErrorMode.accumulate` for multi-error aggregation.
- 38 unit tests covering primitives, combinators, nested paths, discriminated union,
  lazy recursion, firstOf multi-version compatibility, encode failure wrapping, and
  omitNulls.
