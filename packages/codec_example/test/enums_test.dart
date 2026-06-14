import 'package:codec_example/enums.dart';
import 'package:test/test.dart';

void main() {
  test('Enums — 4 种映射 + enumValueField 往返', () {
    final json = {
      'plain': 'beta', // enumByName .name
      'named': 'green', // @CodecEnum .name
      'currency': 392, // valueField code → jpy
      'channel': 'NFC', // @CodecValue String
      'level': 5, // @CodecValue int → high
      'region': 99, // enumValueField code → jp
    };
    final m = Enums.fromJson(json);
    expect(m.plain, Plain.beta);
    expect(m.named, Named.green);
    expect(m.currency, Currency.jpy);
    expect(m.channel, Channel.nfc);
    expect(m.level, Level.high);
    expect(m.region, Region.jp);
    expect(m.toJson(), json);
  });

  test('Enums — 未知 region code 回落到 unknownEnumValue', () {
    final m = Enums.fromJson({
      'plain': 'alpha',
      'named': 'red',
      'currency': 344,
      'channel': 'QR',
      'level': 1,
      'region': 9999, // 未知 → Region.hk
    });
    expect(m.region, Region.hk);
  });
}
