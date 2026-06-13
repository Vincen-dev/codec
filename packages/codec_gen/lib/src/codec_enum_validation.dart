/// 校验某 `@CodecEnum` 的 `@CodecValue` 注解覆盖完整性。
///
/// 返回 [allValues] 中**未**出现在 [annotated] 集合的值名（保留原顺序）。
///
/// 调用方在生成端拿到非空 missing 时报错：当 enum 内**部分**值挂了
/// `@CodecValue` 而另一些没挂，生成的 mapping 会漏值，运行时 encode 漏值
/// 会抛 `EncodeException`——与其在运行时崩溃，不如在 codegen 阶段直接拒绝。
///
/// 注：[annotated] 为空时返回空 missing——"全部不挂"是另一条合法路径
/// （走 `.name` / `valueField`），不属于本函数的报错场景。
List<String> validateCodecValueCoverage({
  required List<String> allValues,
  required Set<String> annotated,
}) {
  if (annotated.isEmpty) return const [];
  return [
    for (final name in allValues)
      if (!annotated.contains(name)) name,
  ];
}
