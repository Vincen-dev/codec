# codec & codec_gen

[![codec](https://img.shields.io/pub/v/codec.svg?label=codec)](https://pub.dev/packages/codec)
[![codec_gen](https://img.shields.io/pub/v/codec_gen.svg?label=codec_gen)](https://pub.dev/packages/codec_gen)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Type-safe, composable JSON encode/decode toolchain for Dart — path-precise errors, zero runtime dependencies.**

| Package | Role | Dependency type |
|---|---|---|
| [`codec`](packages/codec) | Runtime: hand-written / composable codecs, zero third-party dependencies | `dependencies` |
| [`codec_gen`](packages/codec_gen) | Code generator: `@Codable` / `@CodecEnum` annotations → generated codec fields | `dev_dependencies` |

## Contents

- [Installation](#installation)
- [What is this](#what-is-this)
- [Development](#development-monorepo)
- [Publishing](#publishing)

---

## Installation

Runtime only (hand-written codecs):

```bash
dart pub add codec
```

With annotation-driven code generation:

```bash
dart pub add codec
dart pub add dev:codec_gen dev:build_runner
dart run build_runner build --delete-conflicting-outputs
```

---

## What is this

`codec` models JSON encoding and decoding as composable, first-class `Codec<T>` objects:

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

A decode failure throws a structured `DecodeException` (a sealed subclass of `CodecException`); the message carries the exact field path:

```
decode User failed (1 error):
  - $.age: expected int, got: "x" (String)
```

Code that already catches `FormatException` can migrate with zero invasiveness: append `.withFormatExceptions()` on any hand-written codec, or set `exception_style: format` in `build.yaml` for generated codecs.

See each package's README for full details: [codec](packages/codec/README.md) · [codec_gen](packages/codec_gen/README.md).

---

## Development (monorepo)

This repository is a pub workspace; both packages share a single dependency resolution:

```bash
# At the repo root — refresh dependencies for all workspace members
dart pub get

# Analyze / test (run from the respective package directory)
cd packages/codec     && dart analyze && dart test
cd packages/codec_gen && dart analyze && dart test
```

`codec_gen` depends on `codec: ^0.2.0`. In workspace mode, local development resolves directly to `packages/codec` inside this repo — no `path` dependency or `dependency_override` needed.

---

## Publishing

The two packages are **published independently**, and **`codec` must be published first** — `codec_gen` depends on a hosted version of `codec`, so if `codec` is not yet on pub.dev, `codec_gen` cannot resolve its dependency and publishing will fail.

> The default publish target is pub.dev. If your machine's `PUB_HOSTED_URL` points to a read-only mirror, override it back to the official registry before publishing (e.g. `PUB_HOSTED_URL=https://pub.dev`, or unset the variable temporarily).

### First publish (manual — once per package)

pub.dev's automated publishing only works for packages that **already exist** on pub.dev. The very first version of each package must be published manually:

```bash
# codec first: dry-run to validate, then publish; wait for it to appear on pub.dev
cd packages/codec     && dart pub publish --dry-run && dart pub publish
# codec_gen second (its codec:^x constraint can now resolve online)
cd packages/codec_gen && dart pub publish --dry-run && dart pub publish
```

`codec 0.2.1` and `codec_gen 0.2.0` are the first versions published to pub.dev. The 0.1.x line was never released publicly.

### Enable automated publishing (GitHub Actions + OIDC — once per package)

The repo ships with `.github/workflows/publish-codec.yml` and `publish-codec_gen.yml` (both use the official `dart-lang/setup-dart` reusable workflow, authenticating via OIDC — no long-lived tokens required). After the first manual publish, authorize each package on pub.dev once:

1. Log in to pub.dev and open `https://pub.dev/packages/<package-name>/admin`
2. Go to **Automated publishing** → **Enable publishing from GitHub Actions**
3. Set **Repository** to `Vincen-dev/codec` (the same repo for both packages)
4. Set the **Tag pattern** (`{{version}}` is a literal placeholder and must match the glob in the workflow's `on.push.tags`):
   - `codec` package: `codec-v{{version}}`
   - `codec_gen` package: `codec_gen-v{{version}}`
5. (Optional, stricter) Check **Require GitHub Actions environment**, name it (e.g. `pub.dev`), then create a matching environment in GitHub repository Settings → Environments (you can add required reviewers there), and add `environment: pub.dev` under `with:` in the corresponding workflow
6. Save

### Routine releases (tag-driven, fully automated)

Bump `version` and `CHANGELOG.md`, commit and push, then create the tags to trigger CI — `codec` first:

```bash
git tag codec-v0.2.0     && git push origin codec-v0.2.0       # wait for CI to publish codec
git tag codec_gen-v0.2.0 && git push origin codec_gen-v0.2.0   # then publish codec_gen
```

CI runs `dart pub publish` on GitHub's hosted runners, so it is unaffected by local network configuration or registry mirrors.

> Tag-driven publishing is only active once the packages exist on pub.dev (i.e. after the first manual publish described above). Pushing a tag for a version that does not yet exist on pub.dev will cause the workflow to attempt a publish that may conflict; always complete the manual first-publish step before relying on tag automation.

---

## License

[MIT](LICENSE) © Vincen (Zhang Wenjin)
