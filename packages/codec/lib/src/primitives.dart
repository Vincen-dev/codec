part of '../codec.dart';

// ===========================================================================
// 原语 codec
//
// 全部 const 单例，零分配。通过 [Codec] 的 static 字段访问，例：
//   Codec.string / Codec.integer / Codec.dateTime ...
// ===========================================================================

const _maxEpochMillis = 8640000000000000; // DateTime 可表示范围 ±8.64e15 ms

final class _StringCodec extends Codec<String> {
  const _StringCodec();

  @override
  DecodeOutcome<String> doDecode(DecodeContext ctx) {
    final v = ctx.value;
    if (v is String) return DecodeOk(v);
    return ctx.fail(const WrongType('String'));
  }

  @override
  Object? doEncode(String value) => value;
}

final class _BoolCodec extends Codec<bool> {
  const _BoolCodec();

  @override
  DecodeOutcome<bool> doDecode(DecodeContext ctx) {
    final v = ctx.value;
    if (v is bool) return DecodeOk(v);
    if (v is num) return DecodeOk(v != 0);
    if (v is String) {
      switch (v.toLowerCase()) {
        case 'true' || '1' || 'yes':
          return const DecodeOk(true);
        case 'false' || '0' || 'no':
          return const DecodeOk(false);
      }
    }
    return ctx.fail(const WrongType('bool'));
  }

  @override
  Object? doEncode(bool value) => value;
}

final class _IntCodec extends Codec<int> {
  const _IntCodec();

  @override
  DecodeOutcome<int> doDecode(DecodeContext ctx) {
    final v = ctx.value;
    if (v is int) return DecodeOk(v);
    if (v is num) {
      // 拒绝 NaN / ±Infinity（v.toInt() 对 NaN/Infinity 抛 UnsupportedError）
      // 与有小数部分的真浮点（避免 1.5 静默截断到 1）；
      // 但保留 1.0 / -2.0 等"整数浮点"兼容（JS 序列化常见）。
      if (!v.isFinite || v != v.truncateToDouble()) {
        return ctx.fail(BadFormat('integer expected, got $v'));
      }
      return DecodeOk(v.toInt());
    }
    if (v is String) {
      final p = int.tryParse(v);
      if (p != null) return DecodeOk(p);
    }
    return ctx.fail(const WrongType('int'));
  }

  @override
  Object? doEncode(int value) => value;
}

final class _DoubleCodec extends Codec<double> {
  const _DoubleCodec();

  @override
  DecodeOutcome<double> doDecode(DecodeContext ctx) {
    final v = ctx.value;
    if (v is num) return DecodeOk(v.toDouble());
    if (v is String) {
      final p = double.tryParse(v);
      if (p != null) return DecodeOk(p);
    }
    return ctx.fail(const WrongType('double'));
  }

  @override
  Object? doEncode(double value) {
    if (!value.isFinite) {
      throw EncodeException._(
        message: 'non-finite double cannot be JSON-encoded: $value',
        hint: 'double',
      );
    }
    return value;
  }
}

final class _NumCodec extends Codec<num> {
  const _NumCodec();

  @override
  DecodeOutcome<num> doDecode(DecodeContext ctx) {
    final v = ctx.value;
    if (v is num) return DecodeOk(v);
    if (v is String) {
      final p = num.tryParse(v);
      if (p != null) return DecodeOk(p);
    }
    return ctx.fail(const WrongType('num'));
  }

  @override
  Object? doEncode(num value) {
    // int 永远 finite，仅 double 子类可能是 NaN / Infinity
    if (value is double && !value.isFinite) {
      throw EncodeException._(
        message: 'non-finite num cannot be JSON-encoded: $value',
        hint: 'num',
      );
    }
    return value;
  }
}

/// epoch 数字的时间单位。`milliseconds` 与 [DateTime] 内置语义一致，
/// `seconds` 用于后端按 Unix 秒级时间戳传递的场景。
enum DateTimeEpochUnit { milliseconds, seconds }

final class _DateTimeCodec extends Codec<DateTime> {
  const _DateTimeCodec({
    this.epochUnit = DateTimeEpochUnit.milliseconds,
    this.encodeUtc = false,
  });

  final DateTimeEpochUnit epochUnit;
  final bool encodeUtc;

  @override
  DecodeOutcome<DateTime> doDecode(DecodeContext ctx) {
    final v = ctx.value;
    if (v is DateTime) return DecodeOk(v);
    if (v is String) {
      final p = DateTime.tryParse(v);
      if (p != null) return DecodeOk(p);
      return ctx.fail(BadFormat('not ISO-8601: $v'));
    }
    if (v is num) {
      final msNum = epochUnit == DateTimeEpochUnit.seconds ? v * 1000 : v;
      if (!msNum.isFinite || msNum < -_maxEpochMillis || msNum > _maxEpochMillis) {
        return ctx.fail(BadFormat('epoch out of representable DateTime range: $v'));
      }
      return DecodeOk(DateTime.fromMillisecondsSinceEpoch(msNum.toInt()));
    }
    return ctx.fail(
      WrongType('DateTime (ISO-8601 string or epoch ${epochUnit.name})'),
    );
  }

  @override
  Object? doEncode(DateTime value) =>
      (encodeUtc ? value.toUtc() : value).toIso8601String();
}

/// 仅 epoch 数字 ↔ UTC `DateTime` 的双向 codec：decode 出来 isUtc=true，
/// encode 回到数字（int），与 [_DateTimeCodec] 的"数字进 / ISO 字符串出"
/// 不对称形成对照——专为后端协议**双向都用毫秒/秒数字**的场景设计，避免
/// 业务侧 `.year` / `.day` 等访问时被设备时区污染。
final class _DateTimeEpochCodec extends Codec<DateTime> {
  const _DateTimeEpochCodec({required this.unit});

  final DateTimeEpochUnit unit;

  @override
  DecodeOutcome<DateTime> doDecode(DecodeContext ctx) {
    final v = ctx.value;
    if (v is num) {
      final msNum = unit == DateTimeEpochUnit.seconds ? v * 1000 : v;
      if (!msNum.isFinite || msNum < -_maxEpochMillis || msNum > _maxEpochMillis) {
        return ctx.fail(BadFormat('epoch out of representable DateTime range: $v'));
      }
      return DecodeOk(DateTime.fromMillisecondsSinceEpoch(msNum.toInt(), isUtc: true));
    }
    return ctx.fail(WrongType('epoch ${unit.name} number'));
  }

  @override
  Object? doEncode(DateTime value) {
    final ms = value.millisecondsSinceEpoch;
    // 秒级用整除截断（与 Unix `time(0)` 惯例一致）：999ms 不会进位到下一秒
    return unit == DateTimeEpochUnit.seconds ? ms ~/ 1000 : ms;
  }
}

final class _AnyCodec extends Codec<Object?> {
  const _AnyCodec();

  @override
  DecodeOutcome<Object?> doDecode(DecodeContext ctx) =>
      DecodeOk(ctx.value);

  @override
  Object? doEncode(Object? value) => value;
}
