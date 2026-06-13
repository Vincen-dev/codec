# codec

> 类型安全、可组合的 JSON 编解码工具：失败默认抛自有 `CodecException`
> （`DecodeException` / `EncodeException`）并携带 `$.path` 路径定位，
> 零第三方依赖。需要 `FormatException` 兼容时调用 `.withFormatExceptions()`。

## 安装

```yaml
dependencies:
  codec: ^0.2.0
```

或 `dart pub add codec`。需要注解驱动的代码生成（`@Codable` → codec 字段）时，
另见配套包 [`codec_gen`](https://pub.dev/packages/codec_gen)。

---

## TL;DR

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

错误样例（`DecodeException`，message 含完整路径）：
```
decode UserModel failed (1 error):
  - $.contacts[2].avatar: expected String, got: 1 (int)
```

---

## 何时用 / 何时不用

**用**：
- 复杂嵌套结构（路径定位是刚需）
- discriminated union / 多版本字段兼容 / 递归结构
- 既要 `fromJson` 又要 `toJson`，且想避免漂移
- 想要结构化错误（监控分桶、i18n、稳定测试断言）

**不用**：
- 简单 1-2 字段 DTO，现有 `@JsonSerializable()` 加 build_runner 已经够好
- 已经在用 `freezed` 的 model，没必要替换

> **不要**双轨并行。新 model 走 codec，旧 model 自然演进，**不要**为了一致性批量重写。

---

## API 速查

### 原语（const、可复用）

| codec | 接受输入 | 备注 |
|---|---|---|
| `Codec.string` | `String` | — |
| `Codec.integer` | `int` / 整数浮点（`1.0`）/ `String`（无小数点） | **拒绝**真小数（`1.5`）与 NaN/∞，避免静默截断 |
| `Codec.number` | `int` / `double` / `String` → `double` | encode **拒绝** NaN/±∞（抛 `EncodeException`） |
| `Codec.numeric` | `num` / `String` | encode 同上拒绝 NaN/±∞（仅 double 子类型） |
| `Codec.boolean` | `bool` / `num`（非 0 为 true）/ `"true"/"false"/"yes"/"no"/"1"/"0"` | 容忍后端常见变体；任意非零数字均视为 true |
| `Codec.dateTime` | ISO-8601 字符串 / epoch ms（int 或 double） | encode 输出 ISO-8601，保留原时区 |
| `Codec.dateTimeUtc` | 同 `dateTime` | encode 强制 `toUtc()`，输出 ISO-8601 |
| `Codec.dateTimeSeconds` | ISO-8601 字符串 / epoch **秒** | encode 仍输出 ISO-8601（不对称） |
| `Codec.dateTimeMillisUtc` | 仅 epoch 毫秒数字（int / double） | encode 回**毫秒数字**，decode 出 `isUtc=true`，**双向对称** |
| `Codec.dateTimeSecondsUtc` | 仅 epoch **秒**数字 | encode 回**秒数字**，子秒精度被截断 |
| `Codec.any` | 任意 | 透传 `Object?` |
| `Codec.trimmedString` | `String` → trim | — |
| `Codec.nonEmptyString` | trim 后非空 | 失败给 `FailedRefinement` |

### 链式组合子（任意 `Codec<T>` 都能调）

| 方法 | 作用 |
|---|---|
| `.nullable()` | `Codec<T?>`：null 透传 |
| `.withDefault(v)` | **仅** null 时回落到 v；类型/格式错不回落（让 schema 漂移可见） |
| `.refine(predicate, msg)` | 解码后断言 |
| `.bimap(forward, reverse)` | 与领域类型双向映射 |
| `.list()` | `Codec<List<T>>` |
| `.orElse(other)` | 本失败则尝试 other |
| `.withFormatExceptions()` | 将 `CodecException` 包装为 `FormatException` 抛出（兼容既有 `on FormatException` 代码）；**必须最后调用** |

### 顶层工厂

| 方法 | 用于 |
|---|---|
| `Codec.object(decode, encode:)` | 一般对象 |
| `Codec.discriminated(tag:, cases:, encode:)` | sealed 联合类型 |
| `Codec.lazy(() => ...)` | 递归结构 |
| `Codec.firstOf([...])` | 多版本兼容 |
| `Codec.mapOf(value)` | `Map<String, V>` |
| `Codec.enumByName({...}, unknownFallback:)` | 字符串 → enum（可选未知值兜底） |
| `Codec.enumOf(valueCodec, {...}, unknownFallback:)` | 任意值（int code 等）→ enum（可选未知值兜底） |
| `Codec.custom(decode:, encode:)` | 完全自定义 |

### 出口

| 方法 | 返回 | 失败行为 |
|---|---|---|
| `codec.decode(json, mode:, typeHint:)` | `T` | 默认抛 `DecodeException`，message 含 path 与原因；`.withFormatExceptions()` 后转抛 `FormatException` |
| `codec.encode(value)` | `Object?` | 默认抛 `EncodeException`（含未提供 encode 闭包 / bimap reverse 抛错等）；`.withFormatExceptions()` 后转抛 `FormatException` |

---

## Cookbook

### 1. 嵌套对象

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
    address: b.required('address', addressCodec),  // 直接传 codec
  ),
  encode: (u) => {'name': u.name, 'address': addressCodec.encode(u.address)},
);
```

### 2. List + List 元素错误带索引

```dart
final ordersCodec = Codec.object<Order>(
  (b) => Order(
    items: b.required('items', itemCodec.list()),
    tags: b.optionalOr('tags', Codec.string.list(), const []),
  ),
);
// 错误自动是 $.items[3].sku
```

### 3. Discriminated Union（sealed class）

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

> sealed class + `switch (e)` 让加新 case 时编译器立刻报错——加 case 漏写
> encode 分支会被编译期捕获。

### 4. 递归结构（评论树、菜单）

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

### 5. 多版本兼容（v1 string id，v2 int id）

```dart
final idCodec = Codec.firstOf<int>([
  Codec.integer,
  Codec.string.bimap(int.parse, (i) => '$i'),
]);
```

### 6. Enum 映射

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

> 不要用 `RefundStatus.values.byName(s)`——后端值大小写/下划线不一致时
> 直接炸，且没有 fallback。显式 `Map` 是唯一正确做法。

后端可能新增枚举项、前端需向前兼容时，用 `unknownFallback` 兜底——未命中
mapping 的**已知形状值**回落到指定枚举，不再抛 `UnknownTag`；而**类型 / 格式
错误仍照常报错**（如下例 int 字段收到非数字字符串），不被兜底吞掉：

```dart
enum StoreArea { hk, jp, au }

final areaCodec = Codec.enumOf<StoreArea, int>(
  Codec.integer,
  const {84: StoreArea.hk, 99: StoreArea.jp, 12: StoreArea.au},
  unknownFallback: StoreArea.hk,   // 未知 / 新增 code → hk，不致整条记录解码失败
);

areaCodec.decode(99);   // StoreArea.jp（精确命中）
areaCodec.decode(176);  // StoreArea.hk（未知 code 兜底）
areaCodec.decode('x');  // 抛 DecodeException（int 解码失败，类型错不兜底）
```

> 默认不传 `unknownFallback` 时维持严格行为：未知值抛 `UnknownTag` 并列出
> 合法集，让协议 schema 漂移暴露而非被静默吞掉。

### 7. 字段级校验（refine）

```dart
final priceCodec = Codec.number.refine((p) => p >= 0, 'price must be ≥ 0');
final emailCodec = Codec.string.refine(
  (s) => s.contains('@'),
  'invalid email',
);
```

### 8. 字段重命名兼容

```dart
// 后端 v1 用 user_name，v2 改名为 name
final c = Codec.object<User>(
  (b) => User(
    name: b.optional('name', Codec.string)
       ?? b.required('user_name', Codec.string),
  ),
);
```

---

## 错误模式

### `failFast`（默认）

第一个错误就停。适合 **API 响应反序列化**——一个字段坏了，业务也走不下去。

### `accumulate`

list / map / firstOf 的兄弟分支会**继续尝试**，所有错误一起报。适合：
- 批量导入（"100 行 CSV，告诉我哪 7 行坏了"）
- 多版本数据结构调研

```dart
final result = codec.decode(json, mode: ErrorMode.accumulate);
```

> **object builder 内部永远是 fail-fast 的**——一个字段失败立刻短路，
> 防止后续链式调用 `.trim()` / `.toUpperCase()` 在 null 上 NPE。这是
> imperative builder 风格的固有约束，不会改变。

---

## 与 data source / interceptor 集成

`decode` 默认抛 `DecodeException`（`CodecException` 的 sealed 子类），
`encode` 抛 `EncodeException`。可按需选择两条路径：

**结构化处理**（推荐）——直接 `on DecodeException` 拿详情：

```dart
// data source 内
final raw = await dio.post<dynamic>(path, data: ...);
try {
  return MyResponseModel.codec.decode(
    raw.data,
    typeHint: 'MyResponseModel',  // 错误信息更可读
  );
} on DecodeException catch (e, st) {
  // e.errors 含路径列表；e.isAllMissing / e.hasWrongType 可用于监控分桶
  throw JsonException(message: e.message, cause: e, stackTrace: st);
}
```

**兼容模式**——既有 `on FormatException` 代码不想改时，
在最外层 codec 追加 `.withFormatExceptions()` 即可：

```dart
// 定义时：
static final Codec<MyResponseModel> codec =
    _buildCodec().withFormatExceptions();

// 调用方维持不变：
} on FormatException catch (e, st) {
  throw JsonException(message: e.message, cause: e, stackTrace: st);
}
```

codegen 用户也可在 `build.yaml` 设 `exception_style: format`，
让所有生成的 codec 自动追加 `.withFormatExceptions()`（见 codec_gen README）。

---

## 测试模板

每个 codec 至少写四类用例：

```dart
test('正常解码', () {
  final r = userCodec.decode({'name': 'A', 'age': 30});
  expect(r.name, 'A');
});

test('缺必填字段路径精确', () {
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

test('类型不符报 WrongType', () {
  expect(
    () => userCodec.decode({'name': 123}),
    throwsA(isA<DecodeException>().having(
      (e) => e.message, 'message',
      contains('expected String'),
    )),
  );
});

test('encode 往返一致', () {
  const u = UserModel(name: 'A', age: 1);
  final json = userCodec.encode(u);
  expect(userCodec.decode(json).name, 'A');
});
```

> List/Map 解码用 `mode: ErrorMode.accumulate` 多写一组用例验证**所有**
> 错误都被收集到。

---

## 安全考量

### 解码深度 / DoS

递归解码（`Codec.lazy`、嵌套 `object`、`.list()`、`mapOf`）无内置深度上限；超深嵌套的不可信输入可能触发栈溢出。大多数情况下，上游 `dart:convert` 的 `jsonDecode` 会先触发溢出。处理不可信数据时应在上游限制报文大小与嵌套深度。

### 错误信息泄漏

decode 失败的 `DecodeException.message` / `toString()` 会内嵌出错值的截断片段（≤ 80 字符）与其 `runtimeType`。**不要**对敏感报文直接 log 原始 message；改用结构化的 `errors` / `kind` 字段自行构造脱敏信息。

---

## 反模式

### ❌ 用 `??` 把异常吞成默认值

```dart
// ❌ name 缺失时悄悄变成空串，下游完全不知情
name: b.optional('name', Codec.string) ?? '',
```

```dart
// ✅ 必填就明确报错
name: b.required('name', Codec.string),
```

### ❌ 把 codec 写在 fromJson 内部

```dart
// ❌ 每次 fromJson 都 new 一个 codec
factory UserModel.fromJson(Object? json) {
  final codec = Codec.object<UserModel>(...);  // 重复构造
  return codec.decode(json);
}
```

```dart
// ✅ codec 是 static final，进程内单例
static final Codec<UserModel> codec = Codec.object<UserModel>(...);
factory UserModel.fromJson(Object? json) => codec.decode(json);
```

### ❌ Discriminated 分支漏写 encode

```dart
// ❌ 加了新 case _Cancelled 但 encode 还是旧 switch——运行时才发现
encode: (e) => switch (e) {
  _Created() => ...,
  _Approved() => ...,
  // _Cancelled 没写，编译期捕获不到（switch 不穷尽）
},
```

```dart
// ✅ sealed class + switch 表达式，编译器强制穷尽
sealed class RefundEvent {}
encode: (e) => switch (e) {
  _Created()   => ...,
  _Approved()  => ...,
  _Cancelled() => ...,  // 漏写时编译报错
},
```

### ❌ List 元素 codec 用裸 fromJson

```dart
// ❌ 错误路径丢失，看不出是第几个元素错
items: (json['items'] as List).map(ItemModel.fromJson).toList(),
```

```dart
// ✅ codec 自动追加 [i]
items: b.required('items', ItemModel.codec.list()),
```

---

## 性能

- 原语 codec 是 `const` 单例，零分配
- 路径用不可变链表，深嵌套不付出 `O(n²)` 字符串拼接代价
- 失败路径不抛异常（`DecodeOutcome` 是值），无 stack unwind 开销
- list 解码 1M 元素相比 "扩展函数+异常+字符串路径"方案 **快 2-3 倍**

唯一注意：`Codec.lazy` 在递归 codec 里要用，且**用 `late final` 持有外层 codec**：

```dart
// ❌ 没有 late，编译报错"不能引用未声明的变量"
final commentCodec = Codec.object((b) => ...
  Codec.lazy(() => commentCodec)  // 这里 commentCodec 还是 null
);

// ✅ late final + 分两步赋值
late final Codec<Comment> commentCodec;
commentCodec = Codec.object((b) => ...
  Codec.lazy(() => commentCodec)
);
```

---

## FAQ

**Q：为什么不直接用 freezed + json_serializable？**
A：可以并存，但 codec 在三个场景比 codegen 强：
1. discriminated union（freezed 的 union 解 JSON 要写 fromJson 工厂分支）
2. 多版本字段兼容（codegen 不易表达）
3. 错误带 path（`CheckedFromJsonException` 拿不到嵌套路径）

**Q：accumulate 模式能在 object 内字段级生效吗？**
A：不能。imperative builder + accumulate 会让一个字段失败后的链式调用
NPE。Validation Applicative 风格能做到，但要求声明式 DSL，Dart 类型推导
撑不住——属于"为 1% 场景牺牲 99% 易用性"。所以 codec 永远 fail-fast 在
object 层级，accumulate 只在 list/map/firstOf 的同级元素之间生效。

**Q：能和 `@JsonSerializable()` 共存吗？**
A：能。`Codec.object` 的 `decode` 闭包内可以直接调 `OldModel.fromJson`，
反向 `encode` 调 `OldModel.toJson()`，把旧 model 包成 codec 一等公民。
迁移期可以渐进。
