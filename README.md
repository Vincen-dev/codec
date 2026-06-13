# codec & codec_gen

类型安全、可组合的 JSON 编解码工具链，分为两个独立发布的 pub 包：

| 包 | 角色 | 依赖类型 |
|---|---|---|
| [`codec`](packages/codec) | 运行时：手写 / 组合 codec，零第三方依赖 | `dependencies` |
| [`codec_gen`](packages/codec_gen) | 代码生成：`@Codable` / `@CodecEnum` 注解 → 生成 codec 字段 | `dev_dependencies` |

## 安装

只用运行时（手写 codec）：

```bash
dart pub add codec
```

加上注解驱动的代码生成：

```bash
dart pub add codec
dart pub add dev:codec_gen dev:build_runner
dart run build_runner build --delete-conflicting-outputs
```

## 这是什么

`codec` 把 JSON 编解码表达为可组合的一等对象 `Codec<T>`：

```dart
import 'package:codec/codec.dart';

final userCodec = Codec.object<User>(
  (b) => User(
    name: b.required('name', Codec.string),
    age: b.optionalOr('age', Codec.integer, 0),
  ),
  encode: (u) => {'name': u.name, 'age': u.age},
);
```

解码失败默认抛结构化 `DecodeException`（`CodecException` 的 sealed 子类），message 携带精确路径：

```
decode User failed (1 error):
  - $.age: expected int, got: "x" (String)
```

既有 `on FormatException` 代码可通过 `.withFormatExceptions()`（手写 codec）或
`build.yaml` 设 `exception_style: format`（codegen）零侵入兼容。

详见各包 README：[codec](packages/codec/README.md) · [codec_gen](packages/codec_gen/README.md)。

## 开发（monorepo）

本仓库是 pub workspace，两个包共用一次依赖解析：

```bash
# 仓库根:刷新所有 workspace 成员的依赖
dart pub get

# 分析 / 测试(进对应包目录)
cd packages/codec     && dart analyze && dart test
cd packages/codec_gen && dart analyze && dart test
```

`codec_gen` 通过 `codec: ^0.2.0` 依赖 `codec`；workspace 模式下本地开发直接
解析到本仓内的 `packages/codec`，无需 path 依赖或 override。

## 发布

两个包**独立发布**，且 **`codec` 必须先发**——`codec_gen` 依赖其 hosted 版本，
codec 不在 pub.dev 上时 `codec_gen` 解析不到、发布会失败。

> 发布目标默认是 pub.dev。若本机 `PUB_HOSTED_URL` 指向了国内镜像（只读），
> 发布前需覆盖回官方源（如 `PUB_HOSTED_URL=https://pub.dev`，或临时清空该变量）。

### 首次发布（手动，每个包一次）

pub.dev 的自动发布只能用于**已存在**的包，新包的第一个版本必须手动发：

```bash
# 先 codec：dry-run 校验后发布，等它在 pub.dev 上线
cd packages/codec     && dart pub publish --dry-run && dart pub publish
# 再 codec_gen（此时它的 codec:^x 才能在线解析）
cd packages/codec_gen && dart pub publish --dry-run && dart pub publish
```

### 开启自动发布（GitHub Actions + OIDC，每个包配置一次）

仓库已内置 `.github/workflows/publish-codec.yml` 与 `publish-codec_gen.yml`
（调用官方 `dart-lang/setup-dart` reusable workflow，凭 OIDC 鉴权、无需长期令牌）。
首发后，在 pub.dev 上给每个包各授权一次即可：

1. 登录 pub.dev，打开 `https://pub.dev/packages/<包名>/admin`
2. 进入 **Automated publishing** → **Enable publishing from GitHub Actions**
3. **Repository** 填 `Vincen-dev/codec`（两个包都填这同一个仓库）
4. **Tag pattern**（`{{version}}` 为字面占位符，须与工作流 `on.push.tags` 的 glob 对应）：
   - `codec` 包填 `codec-v{{version}}`
   - `codec_gen` 包填 `codec_gen-v{{version}}`
5. （可选，更严）勾 **Require GitHub Actions environment** 并命名（如 `pub.dev`），
   再在 GitHub 仓库 Settings → Environments 建同名环境（可加审批人），
   并在对应工作流的 `with:` 下加一行 `environment: pub.dev`
6. 保存

### 日常发版（tag 驱动，全自动）

改 `version` + `CHANGELOG.md`，提交推送后打 tag 触发（仍是 codec 先）：

```bash
git tag codec-v0.2.0     && git push origin codec-v0.2.0       # 等 CI 发完 codec
git tag codec_gen-v0.2.0 && git push origin codec_gen-v0.2.0   # 再发 codec_gen
```

CI 在 GitHub 海外 runner 上跑 `dart pub publish`，不受本地网络 / 镜像影响。

> ⚠️ `0.1.6` 是手动首发的版本，**不要**再给它打 `codec-v0.1.6` tag——开启自动发布后
> 推一个已存在版本的 tag，CI 会去重发而报错。tag 驱动从下一个版本开始。

## License

[MIT](LICENSE) © Vincen (Zhang Wenjin)
