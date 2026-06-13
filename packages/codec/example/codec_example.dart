// 最小可运行示例:用 Codec.object 手写类型安全的 JSON 编解码,
// 失败时抛携带 `$.path` 的 FormatException。
//
// 运行: dart run example/codec_example.dart
import 'package:codec/codec.dart';

final class UserModel {
  const UserModel({required this.name, this.avatar, required this.age});

  final String name;
  final String? avatar;
  final int age;

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

void main() {
  // 正常解码
  final user = UserModel.fromJson({'name': 'Ada', 'age': 36});
  print('decoded: name=${user.name}, age=${user.age}');

  // 往返编码(omitNulls 省略了 avatar)
  print('encoded: ${user.toJson()}');

  // 失败时携带精确路径
  try {
    UserModel.fromJson({'name': 'Bob', 'age': 'not-a-number'});
  } on FormatException catch (e) {
    print('error: ${e.message}');
  }
}
