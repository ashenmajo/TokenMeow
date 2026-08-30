/// 在 JSON 数据里按路径取值。
/// 路径用英文点分隔，例如 “data.total_credits” 或 “balance_infos.0.total_balance”，
/// 中间的数字表示数组下标。任何一环取不到就返回 null。
dynamic pickByPath(dynamic root, String path) {
  dynamic current = root;
  for (final part in path.split('.')) {
    if (part.isEmpty) return null;
    if (current is Map && current.containsKey(part)) {
      current = current[part];
    } else if (current is List) {
      final index = int.tryParse(part);
      if (index == null || index < 0 || index >= current.length) return null;
      current = current[index];
    } else {
      return null;
    }
  }
  return current;
}

/// 按多个候选路径依次取值，返回第一个取到的。
/// candidates 用英文逗号分隔，例如 “data.available_balance,available_balance”。
dynamic pickFirstByPaths(dynamic root, String candidates) {
  for (final path in candidates.split(',')) {
    final value = pickByPath(root, path.trim());
    if (value != null) return value;
  }
  return null;
}

/// 把接口返回的各种样子的数字（1、"2.50"、"1,234.00"）转成 double，转不了返回 null
double? toDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final cleaned = value.trim().replaceAll(',', '');
    return double.tryParse(cleaned);
  }
  return null;
}

/// 解析“明细字段”的多行文本，每行格式：“显示名=JSON路径”。
/// 返回 显示名 → 候选路径串 的映射；格式不对的行直接忽略。
Map<String, String> parseDetailSpec(String multiLine) {
  final result = <String, String>{};
  for (final line in multiLine.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.contains('=')) continue;
    final eqIndex = trimmed.indexOf('=');
    final label = trimmed.substring(0, eqIndex).trim();
    final path = trimmed.substring(eqIndex + 1).trim();
    if (label.isEmpty || path.isEmpty) continue;
    result[label] = path;
  }
  return result;
}

/// 把金额格式化成带千位分隔符的字符串，例如 1234567.5 -> "1,234,567.50"
String formatAmount(double value) {
  final sign = value < 0 ? '-' : '';
  final fixed = value.abs().toStringAsFixed(2);
  final dotIndex = fixed.indexOf('.');
  final intPart = dotIndex == -1 ? fixed : fixed.substring(0, dotIndex);
  final decimalPart = dotIndex == -1 ? '' : fixed.substring(dotIndex);

  final buffer = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    buffer.write(intPart[i]);
    final digitsLeft = intPart.length - 1 - i;
    if (digitsLeft > 0 && digitsLeft % 3 == 0) buffer.write(',');
  }

  // 末尾的 “.00” 没有信息量，去掉更清爽
  final decimal = decimalPart == '.00' ? '' : decimalPart;
  return '$sign${buffer.toString()}$decimal';
}

/// 紧凑格式，画图表坐标轴用：1500000 -> "1.5M"，12500 -> "12.5k"，105.2 -> "105"
String formatCompact(double value) {
  final abs = value.abs();
  if (abs >= 1000000) {
    final m = value / 1000000;
    return '${m.toStringAsFixed(m.abs() >= 10 ? 0 : 1)}M';
  }
  if (abs >= 1000) {
    final k = value / 1000;
    return '${k.toStringAsFixed(k.abs() >= 20 ? 0 : 1)}k';
  }
  return value.toStringAsFixed(0);
}

/// 带单位的显示文本，例如 “¥ 72.60”；没有单位时只显示数字
String formatWithUnit(double value, String unit) {
  final unitText = unit.isEmpty ? '' : '$unit ';
  return '$unitText${formatAmount(value)}';
}

/// 把时间显示得更友好：“今天 14:30”、“昨天 09:00”、“2026-08-01 12:00”
String formatTime(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(time.year, time.month, time.day);
  final hhmm = '${twoDigits(time.hour)}:${twoDigits(time.minute)}';

  if (thatDay == today) return '今天 $hhmm';
  if (thatDay == today.subtract(const Duration(days: 1))) return '昨天 $hhmm';
  return '${time.year}-${twoDigits(time.month)}-${twoDigits(time.day)} $hhmm';
}

/// 短时间格式，图表横轴用：“08-29 14:30”
String formatTimeShort(DateTime time) {
  return '${twoDigits(time.month)}-${twoDigits(time.day)}'
      ' ${twoDigits(time.hour)}:${twoDigits(time.minute)}';
}

/// 个位数补零：5 -> "05"
String twoDigits(int number) => number.toString().padLeft(2, '0');

/// 月份标签：“2026-08”
String monthLabel(int year, int month) => '$year-${twoDigits(month)}';

/// 把 Exception 转成适合显示的文字（去掉 “Exception: ” 前缀）
String friendlyError(Object error) {
  var text = error.toString();
  if (text.startsWith('Exception: ')) {
    text = text.substring('Exception: '.length);
  }
  return text;
}
