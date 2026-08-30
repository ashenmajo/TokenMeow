import 'package:flutter/material.dart';

import '../models.dart';
import '../utils.dart';

/// 用量趋势图：把历次余额刷新记录画出来。
/// isBarChart = true 画柱状图（每根柱子下面红色是已用、上面绿色是剩余），
/// isBarChart = false 画折线图（绿色线是剩余量、红色线是已用量）。
/// 用 CustomPainter 手绘，不引入第三方图表库。
class TrendChart extends StatelessWidget {
  final List<HistoryPoint> points;
  final bool isBarChart;

  const TrendChart({
    super.key,
    required this.points,
    required this.isBarChart,
  });

  // 图表最多同时画多少个点，太多了挤在一起看不清
  static const maxPoints = 30;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 只画最近的若干条
    final shown = points.length > maxPoints
        ? points.sublist(points.length - maxPoints)
        : points;

    // 图例只显示真的有数据的系列，不放空承诺
    final hasRemain = shown.any((p) => (p.remaining ?? 0) > 0);
    final hasUsed = shown.any((p) => (p.used ?? 0) > 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasRemain || hasUsed)
          Row(
            children: [
              if (hasRemain) ...[
                _dot(const Color(0xFF2E9E5B)),
                const SizedBox(width: 4),
                const Text('剩余', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 16),
              ],
              if (hasUsed) ...[
                _dot(const Color(0xFFD5484C)),
                const SizedBox(width: 4),
                const Text('已用', style: TextStyle(fontSize: 12)),
              ],
            ],
          ),
        if (hasRemain || hasUsed) const SizedBox(height: 8),
        SizedBox(
          height: 220,
          width: double.infinity,
          child: CustomPaint(
            painter: _TrendPainter(
              points: shown,
              isBarChart: isBarChart,
              gridColor: scheme.outlineVariant,
              labelColor: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<HistoryPoint> points;
  final bool isBarChart;
  final Color gridColor;
  final Color labelColor;

  // 与 SplitProgressBar 保持一致的配色
  static const remainColor = Color(0xFF2E9E5B);
  static const usedColor = Color(0xFFD5484C);

  // 画布内边距：左边留给纵轴数字，下面留给横轴时间
  static const padLeft = 52.0;
  static const padRight = 10.0;
  static const padTop = 10.0;
  static const padBottom = 24.0;

  // 纵轴范围（画的时候算）
  double axisMin = 0;
  double axisMax = 1;

  _TrendPainter({
    required this.points,
    required this.isBarChart,
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

    _computeAxisRange();
    _drawAxis(canvas, plotLeft, plotTop, plotRight, plotBottom);

    if (points.isEmpty) return;

    if (isBarChart) {
      _drawBars(canvas, plotLeft, plotTop, plotWidth, plotHeight);
    } else {
      _drawLines(canvas, plotLeft, plotTop, plotWidth, plotHeight);
    }

    _drawXLabels(canvas, plotLeft, plotWidth, plotBottom);
  }

  /// 计算纵轴范围。
  /// 柱状图固定从 0 起（柱状从 0 起才诚实）；折线图在数据变化很小的时候
  /// 自动放大到数据区间附近，否则余额从 3.14 变到 3.14 画出来就是一堵墙。
  void _computeAxisRange() {
    var maxV = 0.0;
    var minV = double.infinity;
    for (final p in points) {
      for (final v in [p.remaining, p.used]) {
        if (v == null) continue;
        if (v > maxV) maxV = v;
        if (v < minV) minV = v;
      }
    }
    if (maxV <= 0) maxV = 1; // 全是 0 / 没有数据
    axisMax = maxV;
    axisMin = 0;

    if (!isBarChart && points.isNotEmpty && minV != double.infinity) {
      final range = maxV - minV;
      // 变化幅度不足最大值的 15% 时，自适应缩放
      if (range < maxV * 0.15) {
        final pad = range * 0.4 + maxV * 0.02;
        axisMin = (minV - pad).clamp(0.0, maxV);
        axisMax = maxV + pad;
      }
    }
    if (axisMax <= axisMin) axisMax = axisMin + 1;
  }

  double _yOf(double top, double plotHeight, double value) {
    final t = ((value - axisMin) / (axisMax - axisMin)).clamp(0.0, 1.0);
    return top + plotHeight * (1 - t);
  }

  /// 画基线、顶部最大值线以及纵轴数字
  void _drawAxis(Canvas canvas, double left, double top, double right,
      double bottom) {
    final linePaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    canvas.drawLine(Offset(left, bottom), Offset(right, bottom), linePaint);
    canvas.drawLine(Offset(left, top), Offset(right, top), linePaint);

    _drawText(canvas, formatCompact(axisMax), Offset(left - 4, top),
        alignRight: true, baselineOffset: 4);
    _drawText(canvas, formatCompact(axisMin), Offset(left - 4, bottom - 8),
        alignRight: true);
  }

  /// 柱状图：每根柱子下面红色是已用、上面绿色是剩余（固定 0 基线）
  void _drawBars(Canvas canvas, double left, double top, double plotWidth,
      double plotHeight) {
    final n = points.length;
    final slot = plotWidth / n;
    final barWidth = (slot * 0.6).clamp(2.0, 28.0);

    final remainPaint = Paint()..color = remainColor;
    final usedPaint = Paint()..color = usedColor;

    for (var i = 0; i < n; i++) {
      final p = points[i];
      final centerX = left + slot * i + slot / 2;
      final barLeft = centerX - barWidth / 2;
      final baseY = _yOf(top, plotHeight, 0); // 柱状图基线固定在 0

      var yCursor = baseY;
      if (p.used != null && p.used! > 0) {
        final h = baseY - _yOf(top, plotHeight, p.used!);
        canvas.drawRect(
          Rect.fromLTWH(barLeft, yCursor - h, barWidth, h),
          usedPaint,
        );
        yCursor -= h;
      }
      if (p.remaining != null && p.remaining! > 0) {
        final topY = _yOf(top, plotHeight, p.remaining!);
        final h = (yCursor - topY).clamp(1.5, plotHeight); // 至少 1.5px 可见
        canvas.drawRect(
          Rect.fromLTWH(barLeft, yCursor - h, barWidth, h),
          remainPaint,
        );
      }
    }
  }

  /// 折线图：绿色线是剩余量，红色线是已用量
  void _drawLines(Canvas canvas, double left, double top, double plotWidth,
      double plotHeight) {
    final n = points.length;
    Offset pointAt(int i, double? value) {
      final x = n == 1 ? left + plotWidth / 2 : left + plotWidth * i / (n - 1);
      final v = ((value ?? axisMin) - axisMin).clamp(0.0, axisMax - axisMin);
      return Offset(x, top + plotHeight * (1 - v / (axisMax - axisMin)));
    }

    final usedPaint = Paint()
      ..color = usedColor
      ..strokeWidth = 1.5;
    final remainPaint = Paint()
      ..color = remainColor
      ..strokeWidth = 2.5;

    for (var i = 0; i < n - 1; i++) {
      if (points[i].used != null || points[i + 1].used != null) {
        canvas.drawLine(pointAt(i, points[i].used),
            pointAt(i + 1, points[i + 1].used), usedPaint);
      }
      canvas.drawLine(
        pointAt(i, points[i].remaining),
        pointAt(i + 1, points[i + 1].remaining),
        remainPaint,
      );
    }

    final dotPaint = Paint()..color = remainColor;
    for (var i = 0; i < n; i++) {
      canvas.drawCircle(pointAt(i, points[i].remaining), 3, dotPaint);
    }
  }

  /// 横轴：首尾时间。所有快照都在同一天时只显示时分，不然全是重复的日期
  void _drawXLabels(
      Canvas canvas, double left, double plotWidth, double bottom) {
    if (points.isEmpty) return;
    final first = points.first.time;
    final last = points.last.time;
    final sameDay = first.year == last.year &&
        first.month == last.month &&
        first.day == last.day;

    String labelOf(DateTime t) => sameDay
        ? '${twoDigits(t.hour)}:${twoDigits(t.minute)}'
        : formatTimeShort(t);

    _drawText(canvas, labelOf(first), Offset(left, bottom + 6));
    _drawText(canvas, labelOf(last), Offset(left + plotWidth - 70, bottom + 6));
  }

  /// 在画布上写文字
  void _drawText(Canvas canvas, String text, Offset position,
      {bool alignRight = false, double baselineOffset = 0}) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 11, color: labelColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final offsetX =
        alignRight ? position.dx - textPainter.width : position.dx;
    textPainter.paint(canvas, Offset(offsetX, position.dy - baselineOffset));
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.isBarChart != isBarChart;
  }
}
