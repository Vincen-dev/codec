import 'package:codec/codec.dart';
import 'package:test/test.dart';

// ═══════════════════════════════════════════════════════════════════
//  Fixtures
// ═══════════════════════════════════════════════════════════════════

class _Person {
  const _Person({required this.name, required this.age});
  final String name;
  final int age;
}

class _Order {
  const _Order({required this.items});
  final List<String> items;
}

sealed class _Event {
  const _Event();
}

class _Created extends _Event {
  const _Created({required this.at});
  final DateTime at;
}

class _Rejected extends _Event {
  const _Rejected({required this.reason});
  final String reason;
}

class _Tree {
  const _Tree({required this.name, required this.children});
  final String name;
  final List<_Tree> children;
}

enum _Color { red, green, blue }

enum _PaymentChannel { cash, card, qr }

// ═══════════════════════════════════════════════════════════════════

void main() {
  group('原语', () {
    test('string 接受 String', () {
      expect(Codec.string.decode('hi'), 'hi');
    });

    test('string 拒绝非 String 并标记 path=\$', () {
      expect(
        () => Codec.string.decode(123),
        throwsA(
          isA<DecodeException>().having(
            (e) => e.message,
            'message',
            allOf(contains(r'$:'), contains('expected String')),
          ),
        ),
      );
    });

    test('integer 兼容字符串', () {
      expect(Codec.integer.decode('42'), 42);
    });

    test('boolean 兼容 0/1 和 true/false 字符串', () {
      expect(Codec.boolean.decode(1), true);
      expect(Codec.boolean.decode(0), false);
      expect(Codec.boolean.decode('true'), true);
      expect(Codec.boolean.decode('false'), false);
    });

    test('dateTime 解 ISO-8601', () {
      final dt = Codec.dateTime.decode('2026-05-08T00:00:00Z');
      expect(dt.year, 2026);
      expect(dt.month, 5);
    });

    test('dateTime 错误格式有 BadFormat 描述', () {
      expect(
        () => Codec.dateTime.decode('not a date'),
        throwsA(
          isA<DecodeException>().having(
            (e) => e.message,
            'message',
            contains('not ISO-8601'),
          ),
        ),
      );
    });

    test('dateTime 接受 int / double epoch 毫秒', () {
      final fromInt = Codec.dateTime.decode(1700000000000);
      final fromDouble = Codec.dateTime.decode(1700000000000.0);
      expect(fromInt.millisecondsSinceEpoch, 1700000000000);
      expect(fromDouble.millisecondsSinceEpoch, 1700000000000);
    });

    test('dateTimeSeconds 把 epoch 当秒解读', () {
      final dt = Codec.dateTimeSeconds.decode(1700000000);
      expect(dt.millisecondsSinceEpoch, 1700000000 * 1000);
    });

    test('dateTimeUtc 编码强制 UTC', () {
      final local = DateTime.utc(2026, 5, 8, 12).toLocal();
      final encoded = Codec.dateTimeUtc.encode(local) as String;
      expect(encoded, endsWith('Z'));
      expect(DateTime.parse(encoded).isUtc, isTrue);
    });

    test('dateTimeMillisUtc decode 数字 → UTC DateTime', () {
      final dt = Codec.dateTimeMillisUtc.decode(1700000000000);
      expect(dt.isUtc, isTrue);
      expect(dt.millisecondsSinceEpoch, 1700000000000);
    });

    test('dateTimeMillisUtc 接受 double 毫秒', () {
      final dt = Codec.dateTimeMillisUtc.decode(1700000000000.0);
      expect(dt.isUtc, isTrue);
      expect(dt.millisecondsSinceEpoch, 1700000000000);
    });

    test('dateTimeMillisUtc 拒绝 ISO 字符串（仅数字 round-trip）', () {
      expect(
        () => Codec.dateTimeMillisUtc.decode('2026-05-08T00:00:00Z'),
        throwsA(isA<DecodeException>()),
      );
    });

    test('dateTimeMillisUtc 拒绝 NaN / Infinity', () {
      for (final v in <double>[
        double.nan,
        double.infinity,
        -double.infinity,
      ]) {
        expect(
          () => Codec.dateTimeMillisUtc.decode(v),
          throwsA(isA<DecodeException>()),
          reason: 'value=$v',
        );
      }
    });

    test('dateTimeMillisUtc encode 输出毫秒数字（不是 ISO 字符串）', () {
      final dt = DateTime.utc(2023, 11, 14, 22, 13, 20);
      final encoded = Codec.dateTimeMillisUtc.encode(dt);
      expect(encoded, isA<int>());
      expect(encoded, 1700000000000);
    });

    test('dateTimeMillisUtc encode 本地 DateTime 也输出绝对毫秒', () {
      // millisecondsSinceEpoch 是绝对时刻，本地 vs UTC DateTime 数值相同
      final utc = DateTime.utc(2023, 11, 14, 22, 13, 20);
      final local = utc.toLocal();
      expect(Codec.dateTimeMillisUtc.encode(local), 1700000000000);
    });

    test('dateTimeMillisUtc round-trip：encode → decode 保 isUtc=true', () {
      final original = DateTime.utc(2026, 5, 8, 12);
      final round = Codec.dateTimeMillisUtc.decode(
        Codec.dateTimeMillisUtc.encode(original),
      );
      expect(round, original);
      expect(round.isUtc, isTrue);
    });

    test('dateTimeSecondsUtc decode 秒级 → UTC DateTime', () {
      final dt = Codec.dateTimeSecondsUtc.decode(1700000000);
      expect(dt.isUtc, isTrue);
      expect(dt.millisecondsSinceEpoch, 1700000000 * 1000);
    });

    test('dateTimeSecondsUtc encode 输出秒数（int，不是 ISO）', () {
      final dt = DateTime.utc(2023, 11, 14, 22, 13, 20);
      final encoded = Codec.dateTimeSecondsUtc.encode(dt);
      expect(encoded, isA<int>());
      expect(encoded, 1700000000);
    });

    test('dateTimeSecondsUtc round-trip', () {
      final original = DateTime.utc(2026, 5, 8, 12, 30, 45);
      final round = Codec.dateTimeSecondsUtc.decode(
        Codec.dateTimeSecondsUtc.encode(original),
      );
      expect(round, original);
      expect(round.isUtc, isTrue);
    });

    test('dateTimeSecondsUtc encode 亚秒精度被截断（秒粒度协议固有）', () {
      final dt = DateTime.utc(2023, 11, 14, 22, 13, 20, 999);
      // 999ms 子秒精度不会保留——秒级协议本身就丢
      expect(Codec.dateTimeSecondsUtc.encode(dt), 1700000000);
    });
  });

  // ═════════════════════════════════════════════════════════════════
  // 边界 / 已知 bug 修复
  // ═════════════════════════════════════════════════════════════════

  group('integer 严格区分整数浮点 vs 真小数', () {
    test('整数浮点（v == truncateToDouble(v)）接受', () {
      expect(Codec.integer.decode(1.0), 1);
      expect(Codec.integer.decode(-2.0), -2);
      expect(Codec.integer.decode(0.0), 0);
      expect(Codec.integer.decode(-0.0), 0);
      // 53 位以内的大整数浮点
      expect(Codec.integer.decode(9007199254740992.0), 9007199254740992);
    });

    test('真小数拒绝，错误描述包含原值', () {
      for (final v in <double>[1.5, -1.5, 0.5, 1e-9, -1e-9, 0.1, 99.9]) {
        final err = expectLater(
          () => Codec.integer.decode(v),
          throwsA(
            isA<DecodeException>().having(
              (e) => e.message,
              'message',
              allOf(contains('integer expected'), contains('$v')),
            ),
          ),
        );
        expect(err, isNotNull, reason: 'value=$v');
      }
    });

    test('NaN / +Infinity / -Infinity 拒绝且不抛 UnsupportedError', () {
      for (final v in <double>[
        double.nan,
        double.infinity,
        -double.infinity,
      ]) {
        expect(
          () => Codec.integer.decode(v),
          throwsA(isA<DecodeException>()),
          reason: 'value=$v',
        );
      }
    });

    test('字符串路径：纯整数字符串 OK，含小数点失败', () {
      expect(Codec.integer.decode('42'), 42);
      expect(Codec.integer.decode('-7'), -7);
      expect(
        () => Codec.integer.decode('1.5'),
        throwsA(isA<DecodeException>()),
      );
      // "1.0" 同样失败：String 路径走 int.tryParse，不接受小数点
      expect(
        () => Codec.integer.decode('1.0'),
        throwsA(isA<DecodeException>()),
      );
    });
  });

  group('number / numeric encode 拒绝非 finite', () {
    test('Codec.number 对 NaN / Infinity 抛 EncodeException', () {
      for (final v in <double>[
        double.nan,
        double.infinity,
        -double.infinity,
      ]) {
        expect(
          () => Codec.number.encode(v),
          throwsA(isA<EncodeException>()),
          reason: 'value=$v',
        );
      }
    });

    test('Codec.numeric 对 NaN / Infinity 抛 EncodeException', () {
      for (final v in <num>[
        double.nan,
        double.infinity,
        -double.infinity,
      ]) {
        expect(
          () => Codec.numeric.encode(v),
          throwsA(isA<EncodeException>()),
          reason: 'value=$v',
        );
      }
    });

    test('Codec.numeric 接受 int（int 永远 finite）', () {
      expect(Codec.numeric.encode(42), 42);
      expect(Codec.numeric.encode(-1), -1);
      expect(Codec.numeric.encode(0), 0);
    });

    test('finite double 正常 encode（含 0.0 / -0.0 / 极值）', () {
      expect(Codec.number.encode(0.0), 0.0);
      expect(Codec.number.encode(-0.0), -0.0);
      expect(Codec.number.encode(1.5), 1.5);
      expect(Codec.number.encode(double.maxFinite), double.maxFinite);
      expect(Codec.number.encode(double.minPositive), double.minPositive);
      expect(Codec.numeric.encode(3.14), 3.14);
    });

    test('EncodeException 类型', () {
      expect(
        () => Codec.number.encode(double.nan),
        throwsA(isA<EncodeException>()),
      );
    });
  });

  group('discriminated encode tag 防覆盖', () {
    final c = Codec.discriminated<_Event>(
      tag: 'type',
      cases: {
        'created': Codec.object<_Event>(
          (b) => _Created(at: b.required('at', Codec.dateTime)),
        ),
        'rejected': Codec.object<_Event>(
          (b) => _Rejected(reason: b.required('reason', Codec.string)),
        ),
      },
      // 故意让 body 也塞一个 'type' 键，模拟用户 misuse
      encode: (e) => switch (e) {
        _Created(:final at) => (
            'created',
            <String, Object?>{
              'type': 'WRONG_FROM_BODY',
              'at': at.toIso8601String(),
            },
          ),
        _Rejected(:final reason) => (
            'rejected',
            <String, Object?>{
              'type': 'WRONG_FROM_BODY',
              'reason': reason,
            },
          ),
      },
    );

    test('body 注入的 tag 不会覆盖 codec 自己的 tag', () {
      final json =
          c.encode(_Created(at: DateTime.utc(2026, 1, 1))) as Map;
      expect(json['type'], 'created');
      expect(json.containsKey('at'), isTrue);
    });

    test('rejected 分支同样不被覆盖', () {
      final json = c.encode(const _Rejected(reason: 'no stock')) as Map;
      expect(json['type'], 'rejected');
      expect(json['reason'], 'no stock');
    });

    test('encode → decode 往返不丢分支', () {
      final created = _Created(at: DateTime.utc(2026, 1, 1));
      final round = c.decode(c.encode(created));
      expect(round, isA<_Created>());
    });
  });

  group('object', () {
    final personCodec = Codec.object<_Person>(
      (b) => _Person(
        name: b.required('name', Codec.string),
        age: b.optionalOr('age', Codec.integer, 0),
      ),
      encode: (p) => {'name': p.name, 'age': p.age},
    );

    test('正常解码', () {
      final p = personCodec.decode({'name': 'Alice', 'age': 30});
      expect(p.name, 'Alice');
      expect(p.age, 30);
    });

    test('age 缺失走默认值', () {
      final p = personCodec.decode({'name': 'A'});
      expect(p.age, 0);
    });

    test('缺 name 报 missing 路径精确到字段', () {
      expect(
        () => personCodec.decode({'age': 1}),
        throwsA(
          isA<DecodeException>().having(
            (e) => e.message,
            'message',
            allOf(contains(r'$.name'), contains('missing required')),
          ),
        ),
      );
    });

    test('name 为 null 报 IsNullField', () {
      expect(
        () => personCodec.decode({'name': null}),
        throwsA(
          isA<DecodeException>().having(
            (e) => e.message,
            'message',
            allOf(contains(r'$.name'), contains('value is null')),
          ),
        ),
      );
    });

    test('encode 还原回 JSON', () {
      expect(
        personCodec.encode(const _Person(name: 'A', age: 1)),
        {'name': 'A', 'age': 1},
      );
    });

    test('未提供 encode 时调用 encode 抛 EncodeException', () {
      final c = Codec.object<_Person>(
        (b) => _Person(name: b.required('name', Codec.string), age: 0),
      );
      expect(
        () => c.encode(const _Person(name: 'a', age: 0)),
        throwsA(isA<EncodeException>()),
      );
    });
  });

  group('list 与嵌套路径', () {
    test('单元素错给精确索引', () {
      expect(
        () => Codec.string.list().decode([1, 2, 3]),
        throwsA(isA<DecodeException>().having(
          (e) => e.message, 'message', contains(r'$[0]'),
        )),
      );
    });

    test('failFast 默认只报第一个', () {
      expect(
        () => Codec.string.list().decode([1, 2, 3]),
        throwsA(isA<DecodeException>().having(
          (e) => e.message, 'message', contains('1 error'),
        )),
      );
    });

    test('accumulate 收集所有错误', () {
      expect(
        () => Codec.string.list().decode(
              [1, 2, 3],
              mode: ErrorMode.accumulate,
            ),
        throwsA(isA<DecodeException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('3 errors'),
            contains(r'$[0]'),
            contains(r'$[2]'),
          ),
        )),
      );
    });

    test('object 内嵌 list 的索引路径', () {
      final orderCodec = Codec.object<_Order>(
        (b) => _Order(items: b.required('items', Codec.string.list())),
      );
      expect(
        () => orderCodec.decode({
          'items': ['a', 1, 'c'],
        }),
        throwsA(
          isA<DecodeException>().having(
            (e) => e.message,
            'message',
            contains(r'$.items[1]'),
          ),
        ),
      );
    });
  });

  group('discriminated union', () {
    final eventCodec = Codec.discriminated<_Event>(
      tag: 'type',
      cases: {
        'created': Codec.object<_Event>(
          (b) => _Created(at: b.required('at', Codec.dateTime)),
        ),
        'rejected': Codec.object<_Event>(
          (b) => _Rejected(reason: b.required('reason', Codec.string)),
        ),
      },
      encode: (e) => switch (e) {
        _Created(:final at) =>
          ('created', {'at': at.toIso8601String()}),
        _Rejected(:final reason) => ('rejected', {'reason': reason}),
      },
    );

    test('已知 tag 走对应分支', () {
      final r = eventCodec.decode({
        'type': 'created',
        'at': '2026-05-08T00:00:00Z',
      });
      expect(r, isA<_Created>());
    });

    test('未知 tag 报 UnknownTag 并列出合法集', () {
      expect(
        () => eventCodec.decode({'type': 'unknown'}),
        throwsA(
          isA<DecodeException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('unknown discriminant tag'),
              contains('created'),
              contains('rejected'),
            ),
          ),
        ),
      );
    });

    test('encode 往返一致', () {
      const e = _Rejected(reason: 'no stock');
      final json = eventCodec.encode(e) as Map<String, Object?>;
      expect(json, {'type': 'rejected', 'reason': 'no stock'});
    });
  });

  group('lazy 递归', () {
    late final Codec<_Tree> tree;
    tree = Codec.lazy(
      () => Codec.object<_Tree>(
        (b) => _Tree(
          name: b.required('name', Codec.string),
          children: b.optionalOr(
            'children',
            Codec.lazy(() => tree).list(),
            const [],
          ),
        ),
      ),
    );

    test('多层嵌套树', () {
      final r = tree.decode({
        'name': 'root',
        'children': [
          {'name': 'a'},
          {
            'name': 'b',
            'children': [
              {'name': 'b1'},
            ],
          },
        ],
      });
      expect(r.name, 'root');
      expect(r.children, hasLength(2));
      expect(r.children[1].children[0].name, 'b1');
    });

    test('深层错误带完整路径', () {
      expect(
        () => tree.decode({
          'name': 'root',
          'children': [
            {
              'name': 'a',
              'children': [
                {'name': 1},
              ],
            },
          ],
        }),
        throwsA(
          isA<DecodeException>().having(
            (e) => e.message,
            'message',
            contains(r'$.children[0].children[0].name'),
          ),
        ),
      );
    });
  });

  group('refine / bimap / nullable / withDefault', () {
    test('refine 失败带消息', () {
      final c = Codec.string.refine((s) => s.length >= 3, 'too short');
      expect(
        () => c.decode('a'),
        throwsA(
          isA<DecodeException>().having(
            (e) => e.message,
            'message',
            contains('too short'),
          ),
        ),
      );
    });

    test('bimap 双向映射', () {
      final c = Codec.string.bimap<int>(int.parse, (i) => '$i');
      expect(c.decode('42'), 42);
      expect(c.encode(7), '7');
    });

    test('nullable 接受 null', () {
      expect(Codec.string.nullable().decode(null), null);
    });

    test('withDefault 在 null 时回落', () {
      expect(Codec.integer.withDefault(99).decode(null), 99);
    });
  });

  group('firstOf 多版本兼容', () {
    test('id 既能接受 int 又能接受 String', () {
      final idCodec = Codec.firstOf<int>([
        Codec.integer,
        Codec.string.bimap(int.parse, (i) => '$i'),
      ]);
      expect(idCodec.decode(42), 42);
      expect(idCodec.decode('42'), 42);
    });

    test('全部失败汇总错误', () {
      final c = Codec.firstOf<int>([Codec.integer]);
      expect(
        () => c.decode({}),
        throwsA(isA<DecodeException>()),
      );
    });
  });

  group('enumByName', () {
    final c = Codec.enumByName<_Color>(const {
      'R': _Color.red,
      'G': _Color.green,
      'B': _Color.blue,
    });

    test('已知值', () {
      expect(c.decode('R'), _Color.red);
    });

    test('未知值列出合法集', () {
      expect(
        () => c.decode('X'),
        throwsA(
          isA<DecodeException>().having(
            (e) => e.message,
            'message',
            allOf(contains('R'), contains('G'), contains('B')),
          ),
        ),
      );
    });

    test('encode 用 mapping key（默认）走 .name', () {
      // 默认 toJson 用 .name，而非 mapping key——若需对齐 mapping，
      // 调用方应显式传 toJson。这里仅验证默认行为。
      expect(c.encode(_Color.red), 'red');
    });

    test('unknownFallback 配置后未知值回落（不报错）', () {
      final c = Codec.enumByName<_Color>(
        const {'R': _Color.red, 'G': _Color.green},
        unknownFallback: _Color.blue,
      );
      expect(c.decode('X'), _Color.blue); // 未知 → 兜底
      expect(c.decode('R'), _Color.red); // 已知仍精确命中
    });
  });

  group('enumOf 任意类型映射', () {
    final paymentCodec = Codec.enumOf<_PaymentChannel, int>(
      Codec.integer,
      const {
        1: _PaymentChannel.cash,
        2: _PaymentChannel.card,
        3: _PaymentChannel.qr,
      },
    );

    test('int → enum decode', () {
      expect(paymentCodec.decode(2), _PaymentChannel.card);
    });

    test('enum → int encode（自动反查 mapping）', () {
      expect(paymentCodec.encode(_PaymentChannel.cash), 1);
      expect(paymentCodec.encode(_PaymentChannel.qr), 3);
    });

    test('未知 int 抛 DecodeException 列出合法集', () {
      expect(
        () => paymentCodec.decode(99),
        throwsA(isA<DecodeException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('unknown discriminant tag "99"'),
            contains('1'),
            contains('2'),
            contains('3'),
          ),
        )),
      );
    });

    test('inner codec 失败（int 解码错）路径冒泡', () {
      expect(
        () => paymentCodec.decode('not-a-number'),
        throwsA(isA<DecodeException>().having(
          (e) => e.message,
          'message',
          contains('expected int'),
        )),
      );
    });

    test('显式 toJson 优先于自动反查', () {
      final c = Codec.enumOf<_PaymentChannel, int>(
        Codec.integer,
        const {1: _PaymentChannel.cash, 2: _PaymentChannel.card},
        toJson: (e) => 99,
      );
      expect(c.encode(_PaymentChannel.cash), 99);
    });

    test('mapping 缺漏值时 encode 抛 EncodeException', () {
      final c = Codec.enumOf<_PaymentChannel, int>(
        Codec.integer,
        const {1: _PaymentChannel.cash},
      );
      expect(
        () => c.encode(_PaymentChannel.qr),
        throwsA(isA<EncodeException>()),
      );
    });

    test('unknownFallback 配置后未知 int 回落到指定枚举值', () {
      final c = Codec.enumOf<_PaymentChannel, int>(
        Codec.integer,
        const {1: _PaymentChannel.cash, 2: _PaymentChannel.card},
        unknownFallback: _PaymentChannel.cash,
      );
      expect(c.decode(99), _PaymentChannel.cash); // 未知 → 兜底
      expect(c.decode(2), _PaymentChannel.card); // 已知仍精确命中
    });

    test('unknownFallback 不吞内层类型错误（int 收到非数字仍报错）', () {
      final c = Codec.enumOf<_PaymentChannel, int>(
        Codec.integer,
        const {1: _PaymentChannel.cash},
        unknownFallback: _PaymentChannel.cash,
      );
      expect(
        () => c.decode('not-a-number'),
        throwsA(isA<DecodeException>()),
      );
    });
  });

  group('注解 const 实例化', () {
    test('@Codable 默认参数', () {
      const a = Codable();
      expect(a.includeIfNull, true);
      expect(a.fieldRename, FieldRename.none);
    });

    test('@Codable 自定义参数', () {
      const a = Codable(includeIfNull: false, fieldRename: FieldRename.snake);
      expect(a.includeIfNull, false);
      expect(a.fieldRename, FieldRename.snake);
    });

    test('@CodecField 完整参数', () {
      const f = CodecField(
        name: 'user_age',
        defaultValue: 0,
        required: true,
        ignore: false,
        codec: '_myCodec',
        includeIfNull: false,
      );
      expect(f.name, 'user_age');
      expect(f.defaultValue, 0);
      expect(f.required, true);
      expect(f.codec, '_myCodec');
      expect(f.includeIfNull, false);
    });

    test('@CodecEnum valueField', () {
      const e = CodecEnum(valueField: 'code');
      expect(e.valueField, 'code');
    });

    test('@CodecValue 接受 String 与 int', () {
      const a = CodecValue('R');
      const b = CodecValue(1);
      expect(a.value, 'R');
      expect(b.value, 1);
    });
  });

  group('omitNulls extension', () {
    test('剔除 value 为 null 的条目', () {
      final m = <String, Object?>{'a': 1, 'b': null, 'c': 'x'};
      expect(m.omitNulls, {'a': 1, 'c': 'x'});
    });

    test('保留 false / 0 / 空串 / 空 list 等 falsy 值', () {
      final m = <String, Object?>{
        'a': false,
        'b': 0,
        'c': '',
        'd': <int>[],
        'e': null,
      };
      expect(m.omitNulls, {'a': false, 'b': 0, 'c': '', 'd': <int>[]});
    });

    test('全 null 返回空 map', () {
      final m = <String, Object?>{'a': null, 'b': null};
      expect(m.omitNulls, isEmpty);
    });

    test('保持插入顺序', () {
      final m = <String, Object?>{'a': 1, 'b': null, 'c': 3};
      expect(m.omitNulls.keys.toList(), ['a', 'c']);
    });

    test('不递归到嵌套 map', () {
      final m = <String, Object?>{
        'outer': <String, Object?>{'inner': null},
      };
      expect(m.omitNulls, {
        'outer': {'inner': null},
      });
    });

    test('返回值类型剔除可空标记', () {
      // 编译期：返回 Map<String, int>，调用方可直接当作 non-null 字典消费。
      final Map<String, int> m = <String, int?>{'a': 1, 'b': null}.omitNulls;
      expect(m['a'], 1);
      expect(m.containsKey('b'), false);
    });
  });

  group('CodecException / DecodeException / EncodeException', () {
    test('默认抛 DecodeException 且不是 FormatException', () {
      expect(
        () => Codec.string.decode(123),
        throwsA(allOf(
          isA<DecodeException>(),
          isA<CodecException>(),
          isNot(isA<FormatException>()),
        )),
      );
    });

    test('DecodeException.errors 携带结构化错误', () {
      try {
        Codec.string.decode(123);
        fail('expected throw');
      } on DecodeException catch (e) {
        expect(e.errors, hasLength(1));
        expect(e.errors.first.kind, isA<WrongType>());
        expect(e.errors.first.actual, 123);
        expect(e.hint, 'String');
      }
    });

    test('DecodeException.isAllMissing 全字段缺失场景', () {
      final c = Codec.object<_Person>(
        (b) => _Person(
          name: b.required('name', Codec.string),
          age: b.optionalOr('age', Codec.integer, 0),
        ),
      );
      try {
        c.decode(<String, Object?>{});
        fail('expected throw');
      } on DecodeException catch (e) {
        expect(e.isAllMissing, isTrue);
      }
    });

    test('DecodeException.hasWrongType 类型错场景', () {
      try {
        Codec.string.list().decode([1, 2, 3], mode: ErrorMode.accumulate);
        fail('expected throw');
      } on DecodeException catch (e) {
        expect(e.hasWrongType, isTrue);
        expect(e.errors, hasLength(3));
      }
    });

    test('encode 失败抛 EncodeException', () {
      final c = Codec.string.bimap<int>(
        int.parse,
        (i) => throw StateError('boom'),
      );
      expect(
        () => c.encode(7),
        throwsA(allOf(
          isA<EncodeException>(),
          isA<CodecException>(),
        )),
      );
    });

    test('EncodeException 携带 cause 与 stackTrace', () {
      final c = Codec.string.bimap<int>(
        int.parse,
        (i) => throw StateError('boom'),
      );
      try {
        c.encode(7);
        fail('expected throw');
      } on EncodeException catch (e) {
        expect(e.cause, isA<StateError>());
        expect(e.causeStackTrace, isNotNull);
        expect(e.hint, 'int');
      }
    });

    test('object 未提供 encode 抛 EncodeException（不是 FormatException 裸抛）', () {
      final c = Codec.object<_Person>(
        (b) => _Person(name: b.required('name', Codec.string), age: 0),
      );
      try {
        c.encode(const _Person(name: 'a', age: 0));
        fail('expected throw');
      } on EncodeException catch (e) {
        expect(e.hint, '_Person');
        expect(e.message, contains('was created without an `encode` argument'));
      }
    });

    test('CodecException sealed：可穷尽 switch', () {
      // 编译通过即说明 sealed 限定生效——switch 不需要 default
      String label(CodecException e) => switch (e) {
            DecodeException() => 'decode',
            EncodeException() => 'encode',
          };
      try {
        Codec.string.decode(123);
      } on CodecException catch (e) {
        expect(label(e), 'decode');
      }
    });

    test('统一 on FormatException 处理仍能接住（兼容模式）', () {
      // 业务侧统一 catch FormatException
      final c = Codec.string.withFormatExceptions();
      Object? caught;
      try {
        c.decode(123);
      } on FormatException catch (e) {
        caught = e;
      }
      expect(caught, isA<FormatException>());
    });

    test('encode 重抛的 EncodeException 保留原始抛出栈（非 _surface 处）', () {
      final c = Codec.string.bimap<int>(int.parse, (i) => throw StateError('boom'));
      try {
        c.encode(7);
        fail('expected throw');
      } catch (e, st) {
        expect(e, isA<EncodeException>());
        // 修复前栈顶会停在 _surface；修复后应反映原始传播路径（doEncode/bimap）。
        expect(st.toString(), isNot(contains('_surface')));
      }
    });
  });

  group('encode 失败包成 EncodeException', () {
    test('object 没传 encode 闭包时抛 EncodeException', () {
      final c = Codec.object<_Person>(
        (b) => _Person(name: b.required('name', Codec.string), age: 0),
      );
      expect(
        () => c.encode(const _Person(name: 'a', age: 0)),
        throwsA(isA<EncodeException>()),
      );
    });

    test('bimap reverse 抛错被包成 EncodeException', () {
      final c = Codec.string.bimap<int>(
        int.parse,
        (i) => throw StateError('boom'),
      );
      expect(
        () => c.encode(7),
        throwsA(isA<EncodeException>().having(
          (e) => e.message, 'message', contains('boom'),
        )),
      );
    });
  });

  group('DateTime 越界/非有限 → DecodeException（不泄漏裸异常）', () {
    final codecs = <String, Codec<DateTime>>{
      'dateTime': Codec.dateTime,
      'dateTimeUtc': Codec.dateTimeUtc,
      'dateTimeSeconds': Codec.dateTimeSeconds,
      'dateTimeMillisUtc': Codec.dateTimeMillisUtc,
      'dateTimeSecondsUtc': Codec.dateTimeSecondsUtc,
    };
    for (final entry in codecs.entries) {
      for (final v in <double>[double.nan, double.infinity, -double.infinity, 1e308]) {
        test('${entry.key} 拒绝 $v', () {
          expect(() => entry.value.decode(v), throwsA(isA<DecodeException>()), reason: '$v');
        });
      }
    }
  });

  group('兜底：codec 内部抛错收敛为 DecodeException', () {
    test('Codec.custom decode 抛错 → DecodeException(UnexpectedError)', () {
      final c = Codec.custom<int>(decode: (ctx) => throw StateError('boom'), encode: (v) => v);
      try {
        c.decode(1);
        fail('expected throw');
      } on DecodeException catch (e) {
        expect(e.errors.single.kind, isA<UnexpectedError>());
      }
    });
    test('refine 谓词抛错 → DecodeException（路径精确）', () {
      final c = Codec.string.refine((s) => throw StateError('boom'), 'msg');
      expect(() => c.decode('x'), throwsA(isA<DecodeException>()));
    });
  });

  group('withFormatExceptions 兼容模式', () {
    test('.withFormatExceptions() 后 decode 抛 FormatException', () {
      final c = Codec.string.withFormatExceptions();
      expect(() => c.decode(123), throwsA(allOf(isA<FormatException>(), isNot(isA<CodecException>()))));
    });
    test('.withFormatExceptions() 后 encode 抛 FormatException', () {
      final c = Codec.string.bimap<int>(int.parse, (i) => throw StateError('x')).withFormatExceptions();
      expect(() => c.encode(7), throwsA(isA<FormatException>()));
    });
    test('正常值不受影响', () {
      expect(Codec.string.withFormatExceptions().decode('ok'), 'ok');
    });
    test('统一 on FormatException 处理：兼容模式下 on FormatException 接住', () {
      final c = Codec.string.withFormatExceptions();
      Object? caught;
      try { c.decode(123); } on FormatException catch (e) { caught = e; }
      expect(caught, isA<FormatException>());
    });
  });
}
