# codec_gen

> `codec` 包的 codegen builder。读 `@Codable` / `@CodecEnum` 注解，
> 生成 `_$xxxCodec` 静态字段。配合运行时包
> [`codec`](https://pub.dev/packages/codec) 使用。

## 安装

```yaml
dependencies:
  codec: ^0.2.0

dev_dependencies:
  codec_gen: ^0.2.0
  build_runner: ^2.4.0
```

或：

```bash
dart pub add codec
dart pub add dev:codec_gen dev:build_runner
```

model 文件：

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

跑生成：

```bash
dart run build_runner build --delete-conflicting-outputs
```

详细注解语义见 [`codec`](https://pub.dev/packages/codec) 包内 `annotations.dart`
的 dartdoc。

## 字段级注解速查

```dart
@Codable(includeIfNull: false)              // 类级：toJson 默认省略 null 字段
final class OrderModel {
  // 简单字段：不挂注解，使用 dart 字段名作为 JSON key
  final String orderId;

  // 重命名 + 默认值
  @CodecField(name: 'total_amount', defaultValue: 0.0)
  final double totalAmount;

  // 字段级覆盖类级 includeIfNull：保留 null
  @CodecField(includeIfNull: true)
  final String? note;

  // 跳过此字段（两种等价写法）
  @CodecIgnore()
  final String? _localCache;
  // 或：@CodecField(ignore: true)

  // 自定义 codec
  @CodecField(codec: '_amountCodec')
  final Decimal price;

  // DateTime 模式（不写字符串引用）
  @CodecField(dateTime: DateTimeMode.utc)
  final DateTime createdAt;            // 走 Codec.dateTimeUtc
  @CodecField(dateTime: DateTimeMode.seconds)
  final DateTime serverTime;           // 走 Codec.dateTimeSeconds

  // 后端发毫秒时间戳 + 业务时区敏感场景：双向数字 ↔ UTC DateTime
  @CodecField(dateTime: DateTimeMode.millisUtc)
  final DateTime txTime;               // decode 出 isUtc=true；encode 回毫秒数字
  @CodecField(dateTime: DateTimeMode.secondsUtc)
  final DateTime expireAt;             // 同上但秒粒度

  // 枚举按字段值映射（枚举无需挂 @CodecEnum，保持 core/domain 纯净）
  @CodecField(enumValueField: 'code')
  final OrderState orderState;         // JSON {"orderState": 3} ↔ code 为 3 的值

  // 未知 code 向前兼容：未命中映射时兜底到指定枚举值（不抛 UnknownTag）
  @CodecField(enumValueField: 'code', unknownEnumValue: StoreArea.hk)
  final StoreArea regionId;            // 未知 / 后端新增 code → hk

  // const List/Map 默认值
  @CodecField(defaultValue: <String>[])
  final List<String> tags;
  @CodecField(defaultValue: <String, int>{})
  final Map<String, int> counters;
}
```

## 构建选项（build.yaml）

### `exception_style`

控制生成的顶层 codec 的异常类型（默认 `codec`）：

```yaml
targets:
  $default:
    builders:
      codec_gen:
        options:
          exception_style: format   # 改为统一抛 FormatException；默认 codec=抛 CodecException
```

| 值 | 行为 |
|---|---|
| `codec`（默认） | 生成的 `_$xxxCodec` 直接使用，`decode` / `encode` 抛 `DecodeException` / `EncodeException` |
| `format` | 生成的 `_$xxxCodec` 自动追加 `.withFormatExceptions()`，`decode` / `encode` 统一抛 Dart 内置 `FormatException` |

设置 `exception_style: format` 是为既有 `on FormatException` 代码提供零侵入的迁移路径，
无需修改任何调用方。需要结构化处理时改用 `codec`（默认），通过
`on DecodeException` / `on EncodeException` 访问 `errors` / `cause` 等字段。

## codegen 期校验

下列错误会在跑 `build_runner` 时直接报出，**不会**等到运行时才暴露：

- `@Codable` 不挂在 class 上 / class 缺默认（unnamed）构造器；
- 字段类型 codec_gen 不认识（提示用 `@CodecField(codec: 'xxx')` 兜底）；
- 嵌套 model 类型未挂 `@Codable`（提示加 `@Codable()` 或字段级 codec）；
- `Map` 的 key 不是 `String`；
- `@CodecValue` 同一 enum 内 `String` / `int` 混用；
- **`@CodecField(enumValueField:)` 用于非 enum 字段 / 枚举上找不到该字段 /
  目标字段类型不在 `int` / `String` / `double` / `num`**；
- **`@CodecField(unknownEnumValue:)` 脱离 `enumValueField` 单独设置 / 其枚举类型
  与字段枚举不一致**：前者属误用，后者会生成编译不过的代码，均在此阶段报错；
- **`@CodecEnum` 部分值漏挂 `@CodecValue`**：避免运行时 encode 漏值崩溃。
  要么全挂，要么全不挂走默认 `.name` / `valueField`。

## 字段名重命名（`fieldRename`）

`@Codable(fieldRename: FieldRename.snake)` 切分规则与 Lodash / inflection
一致：

| Dart 字段 | snake | kebab | pascal | screamingSnake |
|---|---|---|---|---|
| `userName` | `user_name` | `user-name` | `UserName` | `USER_NAME` |
| `userID` | `user_id` | `user-id` | `UserId` | `USER_ID` |
| `URLPath` | `url_path` | `url-path` | `UrlPath` | `URL_PATH` |
| `userIDValue` | `user_id_value` | `user-id-value` | `UserIdValue` | `USER_ID_VALUE` |
| `parseHTTPURLPath` | `parse_httpurl_path` | `parse-httpurl-path` | `ParseHttpurlPath` | `PARSE_HTTPURL_PATH` |

> 纯字符串无法识别 `HTTPURL` 是 `HTTP+URL` 还是单词，连续大写无内嵌 lower
> 时算作单词。后端字段名跟单词分隔的，建议在 dart 字段名上保留显式边界
> （如写成 `parseHttpUrlPath`），或用 `@CodecField(name: '...')` 显式指定。
