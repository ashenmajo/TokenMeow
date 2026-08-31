import 'package:flutter/material.dart';

import '../models.dart';
import '../utils.dart';
import 'provider_badge.dart';
import 'split_progress_bar.dart';

/// 首页的模型卡片。
/// 布局：头像/名称 → 剩余量大数字（右侧状态标签）→ 分段进度条（有总额/已用才画）
/// → 明细字段 → 本月 Token 摘要 → 刷新时间。点击卡片进详情页。
class ModelCard extends StatelessWidget {
  final ModelAccount account;
  final VoidCallback onOpen; // 点击卡片，进详情页
  final VoidCallback onRefresh;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ModelCard({
    super.key,
    required this.account,
    required this.onOpen,
    required this.onRefresh,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preset = presetById(account.providerId);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 第一行：头像 + 名称 / 提供商 + 菜单 ──
              Row(
                children: [
                  ProviderBadge(preset: preset, size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          account.maskedKey.isEmpty
                              ? preset.label
                              : 'API Key    ${account.maskedKey}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  buildCardMenu(),
                ],
              ),
              const SizedBox(height: 12),

              // ── 剩余量：大数字 + 右侧状态标签 ──
              Row(
                children: [
                  Text(
                    '剩余量',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  buildStatusTag(),
                ],
              ),
              const SizedBox(height: 2),
              buildBalanceArea(scheme),
              const SizedBox(height: 8),

              // ── 分段进度条（接口没有总额/已用数据时自动留空） ──
              SplitProgressBar(account: account),
              const SizedBox(height: 8),

              // ── 明细字段（赠送额度、充值余额等，最多两行） ──
              buildDetailRows(scheme),

              // ── 本月 Token 摘要（查过用量才显示） ──
              buildUsageLine(scheme),
              const Spacer(),
              const SizedBox(height: 10),
              Divider(height: 1, color: scheme.outlineVariant),
              const SizedBox(height: 8),

              // ── 底部：最后刷新时间 ──
              Row(
                children: [
                  Icon(Icons.update, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      account.lastRefreshed == null
                          ? '尚未刷新'
                          : '刷新于 ${formatTime(account.lastRefreshed!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  InkResponse(
                    onTap: onRefresh,
                    radius: 18,
                    child: Icon(
                      Icons.refresh,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 卡片右上角的小菜单：查看详情 / 刷新 / 编辑 / 删除
  Widget buildCardMenu() {
    return PopupMenuButton<String>(
      tooltip: '更多操作',
      onSelected: (value) {
        if (value == 'open') onOpen();
        if (value == 'refresh') onRefresh();
        if (value == 'edit') onEdit();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'open',
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18),
              SizedBox(width: 10),
              Text('查看详情'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'refresh',
          child: Row(
            children: [
              Icon(Icons.refresh, size: 18),
              SizedBox(width: 10),
              Text('刷新'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 10),
              Text('编辑'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18),
              SizedBox(width: 10),
              Text('删除'),
            ],
          ),
        ),
      ],
    );
  }

  /// 余额数字：查询中 / 出错 / 正常显示剩余量
  Widget buildBalanceArea(ColorScheme scheme) {
    if (account.isLoading) {
      return Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 10),
          Text('查询中…', style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      );
    }

    if (account.errorMessage != null && account.remaining == null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              account.errorMessage!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.error, fontSize: 13),
            ),
          ),
        ],
      );
    }

    if (account.remaining == null) {
      return Text(
        '——',
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 24),
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: account.displayUnit().isEmpty
                ? ''
                : '${account.displayUnit()} ',
            style: TextStyle(fontSize: 18, color: scheme.onSurfaceVariant),
          ),
          TextSpan(
            text: formatAmount(account.remaining!),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 状态标签：● 正常 / 余额不足 / 已用尽 / 已过期 / Key 有效 / Key 失效 / 查询失败。
  /// 加载中或还没有数据时不显示（仅校验型的 Key 状态校验过就显示）。
  Widget buildStatusTag() {
    if (account.isLoading) return const SizedBox.shrink();

    final isKeyCheckState =
        account.isValidateOnly && account.isKeyValid != null;
    if (!isKeyCheckState) {
      if (account.remaining == null && account.errorMessage == null) {
        return const SizedBox.shrink();
      }
      if (account.remaining == null && account.lastRefreshed == null) {
        return const SizedBox.shrink(); // 从没成功查过，没有状态可言
      }
    }

    final color = account.statusColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            account.statusLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// 明细字段（赠送额度、充值余额等），卡片上最多显示两行；零值的行不显示
  Widget buildDetailRows(ColorScheme scheme) {
    if (account.details.isEmpty) return const SizedBox.shrink();

    final unit = account.displayUnit();
    final visible = account.details.entries
        .where((entry) => entry.value != 0)
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    final rows = visible.take(2).map((entry) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                entry.key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            Text(
              formatWithUnit(entry.value, unit),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }).toList();

    final hidden = visible.length - rows.length;
    if (hidden > 0) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '还有 $hidden 项明细，点击卡片查看',
            style: TextStyle(fontSize: 12, color: scheme.primary),
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  /// 本月用量摘要行：“本月 Token 21M · 消费 ¥42.50”（查过用量才显示）
  Widget buildUsageLine(ColorScheme scheme) {
    final label = account.usageMonthLabel;
    if (label == null || !account.hasUsageApi) return const SizedBox.shrink();
    if (account.usageMonthTokens == null) return const SizedBox.shrink();

    final isCurrentMonth =
        label == monthLabel(DateTime.now().year, DateTime.now().month);
    final prefix = isCurrentMonth ? '本月' : label;
    var text = '$prefix Token ${formatCompact(account.usageMonthTokens!)}';
    if (account.usageMonthCost != null) {
      text +=
          ' · 消费 ${formatWithUnit(account.usageMonthCost!, account.displayUnit())}';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.insights, size: 14, color: scheme.primary),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
