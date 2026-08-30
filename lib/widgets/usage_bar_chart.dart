import 'package:flutter/material.dart';

import '../usage_service.dart';
import '../utils.dart';

/// 每日用量柱状图：一根柱子代表一天的 Token 用量（绿色）。
/// 和趋势图一样用 CustomPainter 手绘，不引第三方图表库。
class UsageBarChart extends StatelessWidget {
  final List<DailyUsage> days;

  const UsageBarChart({super.key, required this.days});

  // 一屏最多画多少天，再多就只画最近的
  static const maxBars = 31;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = days.length > maxBars ? days.sublist(days.length - maxBars) : days;

    final legend = Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration:
              const BoxDecoration(color: Color(0xFF2E9E5B), shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        const Text('当日 Token', style: TextStyle(fontSize: 12)),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        legend,
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          width: double.infinity,
          child: CustomPaint(
            painter: _DailyBarPainter(
              days: shown,
              gridColor: scheme.outlineVariant,
              labelColor: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _DailyBarPainter extends CustomPainter {
  final List<DailyUsage> days;
  final Color gridColor;
  final Color labelColor;

  static const barColor = Color(0xFF2E9E5B);
  static const padLeft = 52.0;
  static const padRight = 10.0;
  static const padTop = 10.0;
  static const padBottom = 24.0;

  _DailyBarPainter({
    required this.days,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plotLeft = padLeft;
    final plotRight = size.width - padRight;
    final plotTop = padTop;
    final plotBottom = size.height - padBottom;
    final plotWidth = plotRight - plotLeft;
    final plotHeight = plotBottom - plotTop;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    // 纵轴最大值
    var maxValue = 0.0;
    for (final d in days) {
      if (d.tokens > maxValue) maxValue = d.tokens;
    }
    if (maxValue <= 0) maxValue = 1;

    // 基线和顶部参考线
    final linePaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(plotLeft, plotBottom), Offset(plotRight, plotBottom), linePaint);
    canvas.drawLine(Offset(plotLeft, plotTop), Offset(plotRight, plotTop), linePaint);
    _drawText(canvas, formatCompact(maxValue), Offset(plotLeft - 4, plotTop),
        alignRight: true, baselineOffset: 4);
    _drawText(canvas, '0', Offset(plotLeft - 4, plotBottom - 8), alignRight: true);

    if (days.isEmpty) return;

    // 柱子：每天一格，柱宽占格子的 60%
    final slot = plotWidth / days.length;
    final barWidth = (slot * 0.6).clamp(2.0, 26.0);
    final barPaint = Paint()..color = barColor;

    for (var i = 0; i < days.length; i++) {
      if (days[i].tokens <= 0) continue;
      final barLeft = plotLeft + slot * i + (slot - barWidth) / 2;
      final barHeight = plotHeight * (days[i].tokens / maxValue);
      canvas.drawRect(
        Rect.fromLTWH(barLeft, plotBottom - barHeight, barWidth, barHeight),
        barPaint,
      );
    }

    // 横轴：首尾日期
    _drawText(canvas, formatDay(days.first.date), Offset(plotLeft, plotBottom + 6));
    _drawText(canvas, formatDay(days.last.date),
        Offset(plotLeft + plotWidth - 70, plotBottom + 6));
  }

  /// 短日期：“08-29”
  String formatDay(DateTime time) =>
      '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';

  void _drawText(Canvas canvas, String text, Offset position,
      {bool alignRight = false, double baselineOffset = 0}) {
    final textPainter = TextPainter(
      text: TextSpan(
          text: text, style: TextStyle(fontSize: 11, color: labelColor)),
      textDirection: TextDirection.ltr,
    )..layout();
    final offsetX = alignRight ? position.dx - textPainter.width : position.dx;
    textPainter.paint(canvas, Offset(offsetX, position.dy - baselineOffset));
  }

  @override
  bool shouldRepaint(covariant _DailyBarPainter oldDelegate) =>
      oldDelegate.days != days;
}
