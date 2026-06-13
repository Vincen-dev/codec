# Changelog

## 0.2.0

### 破坏性变更

- **`CodecException` 不再继承 `FormatException`**：`decode` / `encode` 默认抛
  自有类型 `DecodeException` / `EncodeException`（均为 `CodecException` 的
  sealed 子类），不再抛 Dart 内置 `FormatException`。**迁移**：
  - **codegen 用户**：在 `build.yaml` 中对 `codec_gen` builder 设置
    `exception_style: format`，生成的顶层 codec 将自动追加
    `.withFormatExceptions()`，行为与旧版一致。
  - **手写 codec**：在最外层 codec 调用 `.withFormatExceptions()` 即可将
    所有 `CodecException` 统一转抛为 `FormatException`。
  - **需要结构化处理**：改用 `on DecodeException` / `on EncodeException`，
    通过 `errors` / `isAllMissing` / `hasWrongType`（decode）或 `cause` /
    `causeStackTrace`（encode）获取详情。

### 新增

- **`Codec.withFormatExceptions()` 组合子**：挂在最外层 codec 上，使
  `decode` / `encode` 将所有 `CodecException` 包装为 Dart 内置
  `FormatException` 抛出——为既有 `on FormatException` 代码提供零侵入的
  兼容路径。**必须是链式调用的最后一步**（作用于整条 codec 链）。
- **`UnexpectedError` 错误种类**：顶层兜底，捕获 `decode` / `encode` 内部
  意外抛出的非 `CodecException` 异常，统一收敛为 `DecodeException`，确保
  异常模型气密。

### 修复（健壮性）

- **DateTime 系列 codec 不再泄漏底层异常**：NaN / ±∞ / 越界 epoch 数字
  （`UnsupportedError` / `RangeError`）现统一捕获并转为 `BadFormat`，
  以 `DecodeException` 形式抛出。
- **`refine` 谓词抛错 + 顶层意外异常统一收敛**：`refine` 谓词内部抛出的
  任意异常、以及 `decode` / `encode` 顶层漏出的意外异常，均被收敛为
  `DecodeException`——decode / encode 现在气密，只抛 `CodecException`
  （兼容模式下为 `FormatException`）。

### 测试

- 运行时测试 87 → 114（新增异常体系、DateTime 边界、refine 健壮性等覆盖）。

## 0.1.6

### 新增（unknown 值向前兼容）

- **`Codec.enumOf` / `Codec.enumByName` 新增可选 `unknownFallback`**：解码遇到
  未知 tag（mapping 未命中）时回落到指定枚举值，而非抛 `UnknownTag`。默认
  `null` = 维持原严格行为，**完全向后兼容**。典型场景：后端可能新增 / 调整
  枚举 code，前端需向前兼容、不因单个未知值导致整条记录解码失败。
- **`CodecField.unknownEnumValue`**（注解层）：配合 `enumValueField` 声明未知
  code 的兜底枚举值，codec_gen 透传到生成的
  `Codec.enumOf(..., unknownFallback:)`。codegen 落地见 codec_gen 0.1.6。

### 设计取舍（守住"不静默吞 schema 漂移"）

- `unknownFallback` 只兜底「值解码成功但 tag 未命中」；内层 `valueCodec` 的
  **类型 / 格式错误仍照常冒泡**（如 int 字段收到非数字字符串），不被兜底吞掉。
  与 `withDefault`（仅 null 回落）一脉相承：刻意区分"未知枚举项"（业务可向前
  兼容）与"协议形状错"（必须暴露）。

### 测试

- 新增 3 例：enumOf / enumByName 未知值回落、`unknownFallback` 不吞内层类型
  错误。codec 运行时测试 84 → 87。

### 版本

- runtime 包代码变更（新增 `unknownFallback` / `unknownEnumValue`），`version`
  0.1.5 → 0.1.6，与 CHANGELOG 对齐。

## 0.1.5

### 新增（注解层）

- **`CodecField.enumValueField`**：让枚举字段按枚举实例的某个字段值（如
  `code`）做 JSON 映射，而**枚举本身无需挂 `@CodecEnum`**。适合 core / domain
  层枚举不想耦合序列化框架（import + part 文件）的场景。仅用于 enum 字段，
  目标字段类型须为 `int` / `String` / `double` / `num`；与 `dateTime` 互斥，
  与 `codec` 同时设置时 `codec` 优先。codegen 落地见 codec_gen 0.1.5。

### 历史欠账（清理）

- `pubspec.yaml` 的 `version` 长期停在 `0.1.0`，与 CHANGELOG 已记录到 `0.1.4`
  存在 drift（codec_gen 0.1.4 的「历史欠账」条目已标记待清理）。本次触及
  runtime 包代码（新增 `enumValueField`），顺手把 `version` 补齐到 `0.1.5`，
  与 CHANGELOG 对齐。

## 0.1.4

### 构建 / 工作区

- **接入 pub workspace**：根 `pubspec.yaml` 用 `workspace:` 列出本包，本包
  `pubspec.yaml` 新增 `resolution: workspace`。结果：本包不再生成独立
  `.dart_tool/package_config.json`，统一走根的依赖解析。IDE 在主项目根的
  analyzer 视角下也能解析到 `package:test/test.dart`（之前 `test`/`expect`
  在子包测试文件里爆红是因为根项目用 `flutter_test` 而非 `test`）。
- **SDK 提升**：`^3.4.0` → `^3.6.0`（pub workspace 的下限）。
- **`lints` 降至 `^4.0.0`**：workspace 共用一份依赖解析，要与根项目
  `flutter_lints ^4.0.0`（间接依赖 `lints ^4.0.0`）兼容；本包用到的 lint 集
  在 lints 4.x 已经全覆盖，无功能损失。
- **`.gitignore` 追加 `build/`**：子包跑 `flutter test` 会产出几百个 unit_test
  asset 与 native_assets，全部不入仓。

## 0.1.3

### 新增

- **`Codec.dateTimeMillisUtc`**：epoch 毫秒数字 ↔ UTC `DateTime` 的**双向对称**
  codec。decode 仅接受数字，输出 `isUtc=true` 的 DateTime，避免业务侧 `.year` /
  `.day` 等访问被设备时区污染；encode 回毫秒整数（不是 ISO 字符串），
  与"后端协议双向都用毫秒时间戳"的常见场景对齐。
- **`Codec.dateTimeSecondsUtc`**：同上但秒粒度。encode 用整除截断（与 Unix
  `time(0)` 惯例一致），子秒精度会被秒级协议丢弃。
- **`DateTimeMode.millisUtc` / `DateTimeMode.secondsUtc`**：codec_gen 端新增
  对应枚举值，`@CodecField(dateTime: DateTimeMode.millisUtc)` 直接选取。

### 测试

- 新增 10 条覆盖：UTC isUtc 标志、数字 round-trip、ISO 字符串拒绝、NaN/∞
  拒绝、亚秒精度截断、本地与 UTC DateTime 都输出绝对毫秒。

## 0.1.2

### 新增（注解层）

- **`FieldRename.screamingSnake`**：`userName` → `USER_NAME`。
- **`DateTimeMode` enum** + `CodecField.dateTime` 字段：让 codec_gen 不通过
  字符串引用就能切换到 `Codec.dateTimeUtc` / `Codec.dateTimeSeconds`。
- **`CodecIgnore` 注解**：`@CodecIgnore()` 等价于 `@CodecField(ignore: true)`。

### 文档

- `CodecField.includeIfNull` 的 dartdoc 由"暂未实现字段级覆盖"改为正式语义
  描述（codec_gen 0.1.2 已实装）。
- `CodecField.defaultValue` dartdoc 明确支持 const List / const Map。

## 0.1.1

### 行为变更（修复潜在数据失真）

- `Codec.integer` 拒绝真小数（`1.5`）与 NaN/±∞，仅接受整数浮点（`1.0`）
  与可 parse 的整数字符串。原本静默 `toInt()` 截断会让小数部分悄悄丢失，
  现在显式抛 `BadFormat`。
- `Codec.number` / `Codec.numeric` encode NaN/±∞ 时抛 `EncodeException`，
  把错误收回 codec 错误模型，避免外层 `jsonEncode` 才暴露
  `JsonUnsupportedObjectError`。
- `Codec.discriminated` encode 时，`encode` 闭包返回的 body 即便意外塞入
  与判别字段同名的 key，codec 注入的 tag 也必定胜出（map literal spread
  顺序由 `{tag, ...body}` 改为 `{...body, tag}`）。

### 新增

- `Codec.dateTimeUtc`：encode 时强制 `toUtc().toIso8601String()`，跨时区
  下输出语义一致。
- `Codec.dateTimeSeconds`：epoch 数字按 Unix **秒**解读，避免被默认
  `dateTime` 当成毫秒错读为 1970 附近。
- `Codec.dateTime` 自身：epoch 数字接受 `num`（之前仅 `int`），兼容 JS
  序列化常见的 `1700000000000.0` 这类带小数点的整数毫秒。

### 文档增强

- `Codec.withDefault` / `FieldsReader.optionalOr` 显式声明"仅 null 回落"，
  避免与"任何失败兜底"的直觉冲突；后者请用 `Codec.firstOf` 显式表达。

### 测试

- 新增 15 条边界 case 覆盖以上变更：integer 严格区分整数浮点 vs 真小数、
  number/numeric encode 非 finite、discriminated tag 防覆盖、dateTime 多
  形态 epoch；总测试 58 → 73。

## 0.1.0

- 首个独立版本：从内部代码库抽出为独立 pub 包。
- 公开 API：`Codec<T>` 抽象 + 静态工厂（string / object / discriminated /
  lazy / firstOf / enumByName / mapOf / custom 等）+ 链式组合子（nullable /
  withDefault / refine / bimap / list / orElse）+ `MapOmitNulls` extension。
- 失败抛 Dart SDK 内置 `FormatException`，message 携带 `$.path[idx].field`
  定位与 `ErrorMode.failFast` / `ErrorMode.accumulate` 多错聚合。
- 38 个单元测试覆盖原语 / 组合子 / 嵌套路径 / discriminated / lazy 递归 /
  firstOf 多版本兼容 / encode 失败包装 / omitNulls。
