# Changelog

## 0.2.0

### 依赖升级

- **analyzer 13 / build 4 / source_gen 4 / build_test 3**：迁移到新
  analyzer element model（`Element2` / `LibraryElement2` 等接口），与
  Dart SDK 3.6+ 工具链对齐。
- **`codec` 依赖升至 `^0.2.0`**：对应运行时异常系统重构（`CodecException`
  独立类型、`withFormatExceptions()` 组合子）。

### 新增

- **`build.yaml` 选项 `exception_style`**（`codec` | `format`，默认 `codec`）：
  设置为 `format` 时，生成的每个顶层 codec（`_$xxxCodec`）自动追加
  `.withFormatExceptions()`，使 `decode` / `encode` 统一抛 Dart 内置
  `FormatException`——为依赖 `on FormatException` 的现有代码提供零侵入的
  兼容路径，无需手动修改调用方。

## 0.1.6

### 新增

- **`@CodecField(enumValueField:)` 支持 `unknownEnumValue:`**：声明未知 code 的
  兜底枚举值，生成的顶层 helper 产出
  `Codec.enumOf<E, V>(..., unknownFallback: E.xxx)`。未配则不产出该参数，
  生成代码与行为与 0.1.5 完全一致（向后兼容）。运行时支持见 codec 0.1.6。

### codegen 期校验（新增错误路径）

- `unknownEnumValue` **脱离 `enumValueField` 单独设置**（含被 `codec:` 覆盖的
  情形）→ `build_runner` 阶段抛 `InvalidGenerationSourceError`，不静默忽略。
- `unknownEnumValue` 的**枚举类型与字段枚举不一致** → 抛
  `InvalidGenerationSourceError`，避免生成出编译不过的代码。

### 测试

- 新增 3 例 generator golden test：enumValueField + unknownEnumValue 产出
  `unknownFallback:`、脱离 enumValueField 抛错、枚举类型不一致抛错。
  codec_gen 测试套件合计 64 例。

### 版本

- 生成器代码变更，`version` 0.1.5 → 0.1.6，与 CHANGELOG 及 codec 0.1.6 对齐。

## 0.1.5

### 新增

- **字段级 `@CodecField(enumValueField: 'code')`**：枚举字段按枚举实例的某个
  字段值映射，**枚举无需挂 `@CodecEnum`**（保持 core / domain 纯净，不引入
  codec import 与 part 文件）。与既有 `dateTime:` 模式同构——字段级声明式选
  codec，不写顶层 codec、不写 `codec: '...'` 字符串。优先级
  `codec` > `enumValueField` > `dateTime` > 类型自动推断。
- 生成实现：在 `CodableGenerator` 产出**顶层 helper codec**
  `_$<类名><字段名>EnumCodec = Codec.enumOf<E, V>(...)` 并由字段引用——helper
  顶层 `final` 只构建一次，避免把非 const 的映射 map inline 到每个
  encode/decode 用点重建。helper 按**类名 + 字段名**命名，规避同文件多个
  `@Codable` 引用同一枚举时的顶层名冲突。
- `naming.dart` 新增 `upperFirst`（拼装 helper 变量名用）。

### 行为变更（生成代码格式）

- **codec part 改用超宽 page width 格式化**（`SharedPartBuilder` 传自定义
  `formatOutput`，`DartFormatter(pageWidth: 1 << 16)`）。codec part 的所有
  结构块（`Codec.object` / 构造器 / encode map / 枚举映射 map）本就自带尾随
  逗号驱动换行，单个 reader 调用是单行表达式；长类型名 / 长字段名会让 reader
  调用在 80 列下被**软换行**且末尾缺尾随逗号，触发宿主项目的
  `require_trailing_commas`。放宽 page width 后软换行不再发生，该 lint 从源头
  被**真正避免**，无需在消费侧 build.yaml 配 `ignore_for_file`。

### codegen 期校验（新增错误路径）

- `@CodecField(enumValueField:)` 用于**非 enum 字段** / 枚举上**找不到**该字段 /
  目标字段**类型不在** `int` / `String` / `double` / `num` 时，在
  `build_runner` 阶段抛 `InvalidGenerationSourceError`，不拖到运行时。

### 测试

- 新增 5 例 generator golden test：int / String valueField 映射 + helper 引用、
  同文件多 `@Codable` 引用同枚举的 helper 命名唯一性、非 enum 字段抛错、
  非法 valueField 类型抛错。`codable_generator_test.dart` 14 → 19 例。

## 0.1.4

### 行为变更（生成代码）

- **字段读取调用一律输出显式泛型**：`b.required<T>(...)` / `b.optional<T>(...)` /
  `b.optionalOr<T>(...)` 全部带类型参数，不再依赖 Dart 编译器从构造器参数反推
  `T`。原因：内置 `Codec.any` 是 `Codec<Object?>`，`T` 自身已含 nullable
  信息——挂到 `Object?` 字段上时编译器会反推 `T=Object`（去 nullable），
  与传入 `Codec<Object?>` 类型不匹配而编译失败。显式泛型一次性解决此类
  推断歧义，且未来任何新增 `T` 可空 codec 都不会再撞同款坑。
- **`CodecResolver.resolve` 接口变更**：从返回 `String`（codec 表达式）改为
  返回 `({String expr, String typeArg})` 记录。typeArg 字段携带该 codec
  的 `T` 字符串，generator 端拼装时直接注入显式泛型。嵌套 `List<T?>` /
  `Map<String, V?>` 等场景里 typeArg 与 expr 同步保持元素可空信息。

### 测试

- 影响面：跑 `build_runner build --delete-conflicting-outputs` 全量重生成
  所有 `*.g.dart`，主项目执行 `fvm flutter analyze` 确认零回归。
- **新增 generator golden test**（`test/codable_generator_test.dart`，14 例）：
  借 `build_test` 的 `resolveSources` 拿到 LibraryElement，直接调
  `CodableGenerator.generateForAnnotatedElement` 拿生成字符串做包含断言。
  锁定 b.required / b.optional / b.optionalOr 在原语 / Object? / dynamic /
  嵌套 List / Map / enum / dateTime / 自定义 codec / nullable+required
  各组合下的显式泛型形态——本套件秒级反馈，未来生成代码回归不再依赖
  `build_runner` 全量重跑 + analyze 才能暴露。
- `build_test: ^2.2.0` 新增到 `dev_dependencies`。

### 历史欠账

- `pubspec.yaml` 的 `version` 字段从遗留的 `0.1.0` 一次补齐到 `0.1.4`，
  对齐 CHANGELOG。`codec` runtime 包的 `pubspec.yaml` 版本号 drift 同样
  存在，但本次未触及 runtime 包代码，留作单独清理任务。

### 构建 / 工作区

- **接入 pub workspace**：本包 `pubspec.yaml` 新增 `resolution: workspace`，
  根项目用 `workspace:` 列出本包。子包测试文件里的 `package:test/test.dart`
  现在能被主项目 analyzer 直接解析（不再爆红）。
- **SDK 提升**：`^3.4.0` → `^3.6.0`（pub workspace 的下限）。
- **删除子包 `dependency_overrides`**：原来固定 `analyzer 7.3.0` /
  `analyzer_plugin 0.12.0`，workspace 模式只允许在根声明；这两个 override
  已存在于主 `pubspec.yaml`，值完全一致，删除无副作用。
- **`lints` 降至 `^4.0.0`**：与根项目 `flutter_lints ^4.0.0` 共解析兼容。
- **`.gitignore` 追加 `build/`**：子包跑 `flutter test` 会产出几百个 asset
  文件，全部不入仓。

## 0.1.3

### 新增

- **`DateTimeMode.millisUtc` / `DateTimeMode.secondsUtc`**：分发到新增的
  `Codec.dateTimeMillisUtc` / `Codec.dateTimeSecondsUtc`。适用"后端发毫秒
  时间戳且业务对时区敏感"——decode 出 `isUtc=true`、encode 回数字、双向对称。

## 0.1.2

### 新增

- **`@CodecIgnore()` 简写注解**：等价于 `@CodecField(ignore: true)`，单字段
  跳过场景下更短更醒目。
- **`FieldRename.screamingSnake`**：`userName` → `USER_NAME`，对接 Java/Spring
  后端的枚举与常量风格。
- **`@CodecField(dateTime: DateTimeMode.local/utc/seconds)`**：让新加的
  `Codec.dateTimeUtc` / `Codec.dateTimeSeconds` 可通过注解直接选取，不必再写
  `codec: 'Codec.dateTimeUtc'` 字符串引用。
- **`@CodecField(defaultValue: ...)` 支持 const List / const Map**：嵌套字面量
  也支持，递归解析。元素或 key/value 类型不支持时显式抛 codegen 错。

### 修复

- **字段级 `CodecField.includeIfNull` 实装**：兑现 dartdoc 已声明的语义。
  生成端按字段分桶——保留 null 的字段直接输出，省略 null 的字段用
  `if (v.x != null) 'x': codec.encode(v.x!)` 的 dart map 字面量 if 元素。
  类级 `omitNulls` 调用从此不再被 codec_gen 使用（保留给手写 codec）。

## 0.1.1

### 修复

- **字符串字面量转义**：`@CodecField(defaultValue:)` 与 `@CodecValue` 接受
  含 `'` / `\` / `$` / `\n\r\t` / Unicode 的字符串值时，生成代码不再因
  裸拼接而编译失败。新增 `dartStringLiteral` 工具函数。
- **`FieldRename.snake/kebab/pascal` 连续大写分词**：`userID` → `user_id`、
  `URLPath` → `url_path`、`userIDValue` → `user_id_value`。原算法只识别
  lower→upper 边界，对连续大写后跟 lower 的边界没切（与 Lodash /
  inflection 等主流实现行为对齐；纯连续大写无内嵌 lower 仍视为单词）。
- **`@CodecEnum` 部分挂 `@CodecValue` 在 codegen 阶段拒绝**：原本生成的
  mapping 缺漏值，运行时 encode 漏值才抛 `EncodeException`；现在改在
  生成期抛 `InvalidGenerationSourceError` 并列出未挂注解的值。

### 测试

- **首批单元测试**（之前 0 测）：36 条覆盖 `renameField` 极限场景、
  `lowerFirst`、`dartStringLiteral` 转义顺序与 Unicode、enum 全值覆盖
  校验。

## 0.1.0

- 首个版本：`@Codable` / `@CodecEnum` 注解触发 codegen，生成顶层
  `_$xxxCodec` const / final 字段。
- 字段类型自动识别：原语 / 可空 / 默认值 / `List` / `Map<String,V>` /
  嵌套 model（要求挂 `@Codable`）/ enum（默认 inline `.name`，挂
  `@CodecEnum` 走共享 codec）/ 自引用（自动 `Codec.lazy`）。
- 字段级逃生口 `@CodecField(codec: 'xxx')` 支持任意复杂场景。
- `@Codable(includeIfNull: false)` 类级控制 toJson 自动追加 `.omitNulls`。
