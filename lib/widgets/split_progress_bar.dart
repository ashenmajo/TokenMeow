import 'package:flutter/material.dart';

import '../models.dart';
import '../utils.dart';

/// 分段式进度条：左边绿色表示“剩余”，右边红色表示“已用”，各占比例。
/// 比如剩余 72.6%、已用 27.4%，绿条就占 72.6% 宽、红条占 27.4% 宽。
/// 只有同时知道“总额”和“剩余或已用”才画得出来，否则显示提示文字。
class SplitProgressBar extends StatelessWidget {
  final ModelAccount account;
  final double barHeight;
  final bool showLabels; // 是否显示条下方的剩余/已用文字

  const SplitProgressBar({
    super.key,
    required this.account,
    this.barHeight = 12,
    this.showLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    final usedRatio = account.usedRatio();
    // 没有总额/已用数据就不画，不硬凑（界面上留空即可）
    if (usedRatio == null) return const SizedBox.shrink();

    const remainColor = Color(0xFF2E9E5B); // 绿色：剩余
    const usedColor = Color(0xFFD5484C); // 红色：已用
    final remainRatio = 1.0 - usedRatio;
    final unit = account.displayUnit();

    // 两侧文字：剩余 xx（yy%）、已用 xx（yy%）
    String shareText(double? amount, double ratio) {
      final percent = (ratio * 100).toStringAsFixed(1);
      final amountText = amount == null ? '' : formatWithUnit(amount, unit);
      final text = '$amountText（$percent%）';
      // 没有具体金额时只显示百分比
      return amountText.isEmpty ? '（$percent%）' : text;
    }

    final bar = Row(
      children: [
        if (remainRatio > 0)
          Expanded(
            flex: (remainRatio * 1000).round(),
            child: Container(
              height: barHeight,
              decoration: BoxDecoration(
                color: remainColor,
                borderRadius: BorderRadius.horizontal(
                  left: const Radius.circular(6),
                  right: usedRatio > 0 ? Radius.zero : const Radius.circular(6),
                ),
              ),
            ),
          ),
        if (remainRatio > 0 && usedRatio > 0) const SizedBox(width: 2),
        if (usedRatio > 0)
          Expanded(
            flex: (usedRatio * 1000).round(),
            child: Container(
              height: barHeight,
              decoration: BoxDecoration(
                color: usedColor,
                borderRadius: BorderRadius.horizontal(
                  left: remainRatio > 0 ? Radius.zero : const Radius.circular(6),
                  right: const Radius.circular(6),
                ),
              ),
            ),
          ),
      ],
    );

    if (!showLabels) return bar;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar,
        const SizedBox(height: 6),
        Row(
          children: [
            _legendDot(remainColor),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '剩余 ${shareText(account.remaining, remainRatio)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: remainColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '已用 ${shareText(account.used ?? _remainingOrZero(), usedRatio)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: usedColor),
            ),
            _legendDot(usedColor),
          ],
        ),
      ],
    );
  }

  /// 只有 remaining 没有 used 时，已用量 = total - remaining，用于文字显示
  double? _remainingOrZero() {
    final total = account.total;
    final remaining = account.remaining;
    if (total == null || remaining == null) return null;
    return total - remaining;
  }

  Widget _legendDot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
