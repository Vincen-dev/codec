# codec_gen example

`codec_gen` is a `build_runner`-driven code generator; it has no standalone
`main` to run. Instead, it reads annotations in your project and generates
`*.g.dart` files. The following shows the minimal usage.

## 1. Dependencies

```yaml
dependencies:
  codec: ^0.2.1

dev_dependencies:
  codec_gen: ^0.2.0
  build_runner: ^2.4.0
```

## 2. Annotate a model

```dart
import 'package:codec/codec.dart';

part 'user.g.dart';

@Codable(includeIfNull: false)
final class User {
  const User({required this.name, required this.age, this.avatar});

  final String name;
  final int age;

  @CodecField(name: 'avatar_url')
  final String? avatar;

  static final Codec<User> codec = _$userCodec;
  factory User.fromJson(Object? json) => codec.decode(json);
  Object? toJson() => codec.encode(this);
}
```

## 3. Run the generator

```bash
dart run build_runner build --delete-conflicting-outputs
```

`build_runner` generates `user.g.dart` containing `_$userCodec`. After that,
`User.fromJson(...)` / `user.toJson()` are ready to use. On failure, the codec
throws a `DecodeException` with a `$.path` error location (catch with
`on DecodeException`).

For `FormatException` compatibility, either set `exception_style: format` in
`build.yaml` (the generator appends `.withFormatExceptions()` to every
top-level codec automatically), or call `.withFormatExceptions()` manually on
the outermost codec at the call site.

For the full annotation reference (field renaming, enum mapping, DateTime
modes, default values, etc.) see the
[`codec_gen` README](../README.md).
