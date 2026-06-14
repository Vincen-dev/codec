import 'package:codec/codec.dart';
import 'package:codec_example/scalars.dart';
import 'package:test/test.dart';

void main() {
  test('Primitives roundtrip', () {
    final json = {
      's': 'hi',
      'i': 3,
      'd': 1.5,
      'n': 7,
      'b': true,
      'any': [1, 'x'],
    };
    final m = Primitives.fromJson(json);
    expect(m.s, 'hi');
    expect(m.i, 3);
    expect(m.d, 1.5);
    expect(m.n, 7);
    expect(m.b, true);
    expect(m.any, [1, 'x']);
    expect(m.toJson(), json);
  });

  // 固定绝对时刻 2021-01-02T03:04:05.000Z = 1609556645000ms = 1609556645s
  const epochMs = 1609556645000;
  const epochSecs = 1609556645;
  Map<String, Object?> timesInput() => {
        'local': '2021-01-02T03:04:05.000',
        'utc': '2021-01-02T03:04:05.000Z',
        'seconds': epochSecs,
        'millisUtc': epochMs,
        'secondsUtc': epochSecs,
      };

  test('Times decode — 绝对时刻不受运行机时区影响', () {
    final t = Times.fromJson(timesInput());
    expect(t.utc.millisecondsSinceEpoch, epochMs);
    expect(t.utc.isUtc, isTrue);
    expect(t.millisUtc.millisecondsSinceEpoch, epochMs);
    expect(t.millisUtc.isUtc, isTrue);
    expect(t.secondsUtc.millisecondsSinceEpoch, epochMs);
    expect(t.secondsUtc.isUtc, isTrue);
    // local 是壁钟（无换算），按字段断言
    expect(t.local.year, 2021);
    expect(t.local.hour, 3);
    expect(t.local.isUtc, isFalse);
  });

  test('Times encode — 形态断言（TZ 无关部分精确，TZ 相关仅类型）', () {
    final json = Times.fromJson(timesInput()).toJson()! as Map<String, Object?>;
    expect(json['millisUtc'], epochMs); // 回毫秒整数
    expect(json['secondsUtc'], epochSecs); // 回秒整数
    expect(json['utc'], '2021-01-02T03:04:05.000Z'); // 带 Z 的 ISO
    expect(json['local'], '2021-01-02T03:04:05.000'); // 本地壁钟 ISO（无 Z）
    expect(json['seconds'], isA<String>()); // seconds 模式 encode 出 ISO（不对称）
  });

  test('Times decode∘encode 幂等', () {
    final once = Times.fromJson(timesInput()).toJson();
    final twice = Times.fromJson(once).toJson();
    expect(twice, once);
  });

  test('Account — rename / 默认值 / required / ignore / includeIfNull', () {
    final m = Account.fromJson({
      'account_id': 'a1',
      'name': 'Ada',
      'login_count': 5,
    });
    expect(m.accountId, 'a1');
    expect(m.displayName, 'Ada');
    expect(m.loginCount, 5);
    expect(m.cachedToken, ''); // ignore → 构造器默认
    expect(m.toJson(), {'account_id': 'a1', 'name': 'Ada', 'login_count': 5});
  });

  test('Account — 缺省与 null 字段省略', () {
    final m = Account.fromJson({'account_id': 'a2'});
    expect(m.displayName, isNull);
    expect(m.loginCount, 0); // defaultValue
    // name 省略（nullable + includeIfNull:false）；cached_token 从不写
    expect(m.toJson(), {'account_id': 'a2', 'login_count': 0});
  });

  test('Account — 缺失 required 字段抛 DecodeException', () {
    // 安全网：若生成器把 required 弱化成 optional，此用例不再抛、即变红。
    expect(
      () => Account.fromJson(<String, Object?>{'login_count': 0}),
      throwsA(isA<DecodeException>()),
    );
  });
}
