# codec_gen 示例

`codec_gen` 是 `build_runner` 驱动的代码生成器，没有独立可运行的 `main`——
它在你的项目里读注解、生成 `*.g.dart`。以下是最小用法。

## 1. 依赖

```yaml
dependencies:
  codec: ^0.2.0

dev_dependencies:
  codec_gen: ^0.2.0
  build_runner: ^2.4.0
```

## 2. 给 model 挂注解

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

## 3. 生成

```bash
dart run build_runner build --delete-conflicting-outputs
```

`build_runner` 会生成 `user.g.dart`，内含 `_$userCodec`。之后
`User.fromJson(...)` / `user.toJson()` 即可用，失败默认抛带 `$.path` 的
`DecodeException`（`on DecodeException` 捕获）。需要 `FormatException` 兼容时，
在 `build.yaml` 中设 `exception_style: format`（生成 codec 自动追加
`.withFormatExceptions()`），或在手写调用点对最外层 codec 追加
`.withFormatExceptions()`。

完整注解语义（字段重命名、枚举映射、DateTime 模式、默认值等）见
[`codec_gen` README](../README.md)。
