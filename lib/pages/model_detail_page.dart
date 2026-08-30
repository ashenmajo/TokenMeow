import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_service.dart';
import '../models.dart';
import '../usage_service.dart';
import '../utils.dart';
import '../widgets/add_model_dialog.dart';
import '../widgets/split_progress_bar.dart';
import '../widgets/trend_chart.dart';
import '../widgets/usage_bar_chart.dart';

/// 模型详情页。从上到下：余额总览 → 用量概览 → 各模型用量占比 → 用量趋势
/// → API 信息（默认折叠）→ 原始返回（开发者模式才显示），底部是固定操作栏。
class ModelDetailPage extends StatefulWidget {
  final ModelAccount account;
  final AppSettings settings;
  final VoidCallback onChanged; // 数据变化后通知上一页保存
  final VoidCallback onDeleteRequested; // 请求删除，由上一页执行并关闭本页

  const ModelDetailPage({
    super.key,
    required this.account,
    required this.settings,
    required this.onChanged,
    required this.onDeleteRequested,
  });

  @override
  State<ModelDetailPage> createState() => _ModelDetailPageState();
}

class _ModelDetailPageState extends State<ModelDetailPage> {
  bool isBarChart = true; // 用量趋势：true 柱状图 / false 折线图
  bool showApiKey = false; // 是否明文显示 API Key

  // ── 折叠区块的定位用 Key（展开时滚到可见） ──
  final GlobalKey _apiInfoKey = GlobalKey();
  final GlobalKey _rawKey = GlobalKey();

  // ── 本月用量 ──
  UsageReport? usageReport;
  String? usageError;
  bool usageLoading = false;
  late int usageYear;
  late int usageMonth;

  ModelAccount get account => widget.account;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    usageYear = now.year;
    usageMonth = now.month;
    // 配置了用量接口且已经填过 Token，就自动查一次本月用量
    if (account.hasUsageApi && account.usageToken.trim().isNotEmpty) {
      _loadUsage();
    }
  }

  // ─────────────────────────── 数据操作 ───────────────────────────

  /// 刷新余额（也顺带静默刷新用量摘要）
  Future<void> refresh() async {
    if (account.isLoading) return;
    setState(() {
      account.isLoading = true;
      account.errorMessage = null;
    });

    BalanceResult? result;
    String? error;
    try {
      result = await fetchBalance(account, settings: widget.settings);
    } catch (e) {
      error = friendlyError(e);
    }
    if (!mounted) return;

    setState(() {
      account.isLoading = false;
      if (result != null) {
        account.remaining = result.remaining;
        account.used = result.used;
        account.total = result.total;
        account.details = result.details;
        account.currencyCode = result.currencyCode;
        account.isAvailable = result.isAvailable;
        account.rawResponse = result.rawJson;
        account.lastRefreshed = DateTime.now();
        account.appendHistory();
      } else {
        account.errorMessage = error;
      }
    });
    widget.onChanged();
    _loadUsageIfConfigured();
  }

  /// 查询当前选中月份的用量，并把摘要记录到账号上（首页卡片显示用）
  Future<void> _loadUsage() async {
    if (usageLoading) return;
    setState(() {
      usageLoading = true;
      usageError = null;
    });
    try {
      final report = await fetchUsage(
        account,
        widget.settings,
        year: usageYear,
        month: usageMonth,
      );
      if (!mounted) return;
      setState(() {
        usageReport = report;
        usageLoading = false;
        if (usageYear == DateTime.now().year &&
            usageMonth == DateTime.now().month) {
          // 只有“本月”的数据才记录摘要，历史月份不覆盖
          account.recordUsageSummary(
            tokens: report.totalTokens,
            cost: report.totalCost,
            cacheHitRate: report.cacheHitRate,
            year: usageYear,
            month: usageMonth,
          );
          widget.onChanged();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        usageReport = null;
        usageError = friendlyError(e);
        usageLoading = false;
      });
    }
  }

  /// 配置了用量接口且填了 Token 才去查
  void _loadUsageIfConfigured() {
    if (account.hasUsageApi && account.usageToken.trim().isNotEmpty) {
      _loadUsage();
    }
  }

  /// 切换上/下一个月（下一个超出当前月份时按钮禁用）
  void _shiftMonth(int delta) {
    final now = DateTime.now();
    var month = usageMonth + delta;
    var year = usageYear;
    if (month < 1) {
      month = 12;
      year -= 1;
    }
    if (month > 12) {
      month = 1;
      year += 1;
    }
    // 不能翻到未来
    if (DateTime(year, month).isAfter(DateTime(now.year, now.month))) return;

    setState(() {
      usageYear = year;
      usageMonth = month;
      usageReport = null;
    });
    if (account.usageToken.trim().isNotEmpty) {
      _loadUsage();
    }
  }

  /// 弹出填写网页 Token 的对话框，保存后立刻查一次用量
  Future<void> _showTokenDialog() async {
    final controller = TextEditingController(text: account.usageToken);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('填入用量 Token'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '用量数据来自平台网页版，需要网页登录 Token（不是 API Key）：\n'
                '1. 浏览器打开平台并登录\n'
                '2. 按 F12 打开控制台，执行下面的命令\n'
                '3. 复制结果粘贴到下面（Token 短期有效，失效后重新获取）',
                style: TextStyle(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const SelectableText(
                  'JSON.parse(localStorage.userToken).value',
                  style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '网页 Token',
                  hintText: '粘贴到这里',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存并查询'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;

    setState(() => account.usageToken = controller.text.trim());
    widget.onChanged(); // Token 保存下来，下次不用再填
    _loadUsage();
  }

  /// 跳到编辑弹窗（复用首页的弹窗，编辑结果通过回调更新）
  Future<void> edit() async {
    final result = await showDialog<ModelAccount>(
      context: context,
      builder: (context) => AddModelDialog(existing: account),
    );
    if (result == null || !mounted) return;
    // 把编辑结果写回当前账号对象（id 相同）
    account.name = result.name;
    account.providerId = result.providerId;
    account.balanceUrl = result.balanceUrl;
    account.apiKey = result.apiKey;
    account.unit = result.unit;
    account.pathCurrency = result.pathCurrency;
    account.pathDetails = result.pathDetails;
    account.pathRemaining = result.pathRemaining;
    account.pathUsed = result.pathUsed;
    account.pathTotal = result.pathTotal;
    account.usageAmountUrl = result.usageAmountUrl;
    account.usageCostUrl = result.usageCostUrl;
    account.keyCheckUrl = result.keyCheckUrl;
    setState(() {});
    widget.onChanged();
    refresh();
  }

  Future<void> delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账号'),
        content: Text('确定要删除「${account.name}」吗？删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.onDeleteRequested();
  }

  Future<void> copyText(String text, String tip) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tip), behavior: SnackBarBehavior.floating),
    );
  }

  // ─────────────────────────── 界面 ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(account.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: account.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: refresh,
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) {
              if (value == 'edit') edit();
              if (value == 'delete') delete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('编辑账号'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18),
                    SizedBox(width: 10),
                    Text('删除账号'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          balanceOverviewCard(Theme.of(context).colorScheme),
          if (account.hasUsageApi) ...[
            usageOverviewCard(Theme.of(context).colorScheme),
            if (usageReport != null && usageReport!.models.isNotEmpty)
              modelShareCard(Theme.of(context).colorScheme),
          ],
          trendCard(Theme.of(context).colorScheme),
          apiInfoCard(Theme.of(context).colorScheme),
          if (widget.settings.developerMode && account.rawResponse != null)
            rawResponseCard(Theme.of(context).colorScheme),
        ],
      ),
    );
  }

  /// 圆角卡片容器
  Widget card(List<Widget> children) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
    );
  }

  // ───────────────── 1. 余额总览卡 ─────────────────

  Widget balanceOverviewCard(ColorScheme scheme) {
    return card([
      Row(
        children: [
          Text(
            '剩余量',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          buildStatusTag(),
        ],
      ),
      const SizedBox(height: 4),
      buildBalanceNumber(scheme),
      const SizedBox(height: 4),
      // 分段进度条：接口有总额/已用才显示，没有就不画
      SplitProgressBar(account: account, barHeight: 14, showLabels: false),
      const SizedBox(height: 12),
      Divider(height: 1, color: scheme.outlineVariant),
      const SizedBox(height: 10),
      // 仅校验型账号（OpenAI 等无余额接口）：显示 Key 状态 + 手动记录余额
      if (account.isValidateOnly)
        buildValidateOnlyFooter(scheme)
      else
        buildDetailColumns(scheme),
      // Key 掩码行：复制按钮就在它右边，一眼知道复制的是什么
      if (account.maskedKey.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Text(
                'Key: ${account.maskedKey}',
                style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              InkResponse(
                onTap: () => copyText(account.apiKey, 'API Key 已复制'),
                radius: 16,
                child: Icon(Icons.copy,
                    size: 15, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
    ]);
  }

  /// 仅校验型账号的余额卡底部：Key 校验状态 + 手动记录余额按钮
  Widget buildValidateOnlyFooter(ColorScheme scheme) {
    final valid = account.isKeyValid;
    final icon = valid == null
        ? Icons.help_outline
        : (valid ? Icons.check_circle_outline : Icons.cancel_outlined);
    final iconColor = valid == null
        ? scheme.onSurfaceVariant
        : (valid ? const Color(0xFF2E9E5B) : scheme.error);
    final text = valid == null
        ? '该提供商不支持余额查询，尚未校验 Key'
        : valid
        ? 'Key 有效 · ${account.availableModels ?? 0} 个可用模型'
        : 'Key 已失效，请到提供商控制台更换';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: _showManualBalanceDialog,
          icon: const Icon(Icons.savings_outlined, size: 18),
          label: Text(account.remaining == null ? '记录余额' : '更新余额'),
        ),
      ],
    );
  }

  /// 手动记录余额：填当前余额（从提供商控制台看一眼），
  /// 写进剩余量并记一次快照，趋势图和状态标签照常生效。
  Future<void> _showManualBalanceDialog() async {
    final controller = TextEditingController(
      text: account.remaining == null ? '' : formatAmount(account.remaining!),
    );
    final dialogScheme = Theme.of(context).colorScheme;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('记录余额'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '该提供商不支持余额查询。去提供商控制台看一眼当前余额填到这里，'
                '应用会记录每次快照并画出趋势。',
                style: TextStyle(
                  fontSize: 13,
                  color: dialogScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: account.displayUnit().isEmpty
                      ? '当前余额'
                      : '当前余额（${account.displayUnit()}）',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;

    final value = double.tryParse(controller.text.trim().replaceAll(',', ''));
    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请填写数字'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      account.remaining = value;
      account.errorMessage = null;
      account.appendHistory(); // 手动记录也算一个快照
    });
    widget.onChanged();
  }

  Widget buildStatusTag() {
    // 加载中或从没成功查过：不显示标签
    if (account.isLoading) return const SizedBox.shrink();
    if (account.remaining == null && account.lastRefreshed == null) {
      return const SizedBox.shrink();
    }

    final color = account.statusColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildBalanceNumber(ColorScheme scheme) {
    if (account.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (account.remaining == null) {
      if (account.errorMessage != null) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 16, color: scheme.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                account.errorMessage!,
                style: TextStyle(fontSize: 13, color: scheme.error),
              ),
            ),
          ],
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '——',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 28),
        ),
      );
    }
    final unit = account.displayUnit();
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: unit.isEmpty ? '' : '$unit ',
            style: TextStyle(fontSize: 20, color: scheme.onSurfaceVariant),
          ),
          TextSpan(
            text: formatAmount(account.remaining!),
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// 余额明细：横向三栏（总额度 / 已使用 / 其他明细），没有就不显示
  Widget buildDetailColumns(ColorScheme scheme) {
    final unit = account.displayUnit();
    final columns = <String, double?>{
      '总额度': account.total,
      '已使用': account.used,
      ...account.details,
    };

    final visible = <MapEntry<String, double>>[];
    columns.forEach((label, value) {
      if (value != null && visible.length < 3) {
        visible.add(MapEntry(label, value));
      }
    });
    if (visible.isEmpty) {
      return Text(
        '该接口未提供更多明细',
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      );
    }

    return Row(
      children: [
        for (final entry in visible)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatWithUnit(entry.value, unit),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ───────────────── 2. 用量概览 + 3. 各模型占比 ─────────────────

  Widget usageOverviewCard(ColorScheme scheme) {
    final now = DateTime.now();
    final isCurrentMonth = usageYear == now.year && usageMonth == now.month;

    return card([
      Row(
        children: [
          sectionTitle('用量概览'),
          const Spacer(),
          if (usageLoading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          IconButton(
            tooltip: '上一个月',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shiftMonth(-1),
          ),
          Text(
            '$usageYear-${twoDigits(usageMonth)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          IconButton(
            tooltip: '下一个月',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right),
            onPressed: isCurrentMonth ? null : () => _shiftMonth(1),
          ),
        ],
      ),
      buildUsageBody(scheme),
    ]);
  }

  Widget buildUsageBody(ColorScheme scheme) {
    // 还没填 Token：显示引导
    if (account.usageToken.trim().isEmpty && usageError == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '查询用量需要在平台网页版登录后获取 Token（短期有效）。',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _showTokenDialog,
            icon: const Icon(Icons.key_outlined, size: 18),
            label: const Text('填入 Token'),
          ),
        ],
      );
    }

    // 出错（最常见是 Token 过期）：显示原因 + 更新入口
    if (usageError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 16, color: scheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  usageError!,
                  style: TextStyle(fontSize: 13, color: scheme.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _showTokenDialog,
            icon: const Icon(Icons.key_off_outlined, size: 18),
            label: const Text('更新 Token'),
          ),
        ],
      );
    }

    final report = usageReport;
    if (report == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '查询中…',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
      );
    }

    // ── 双栏大数字：总 Token | 消费 ──
    final unit = account.displayUnit();
    final costText = report.totalCost == null
        ? '—'
        : formatWithUnit(report.totalCost!, unit);
    final hitRate = report.cacheHitRate;
    final hitText = hitRate == null
        ? '暂无'
        : '${(hitRate * 100).toStringAsFixed(1)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: usageTile(
                '总 Token',
                formatCompact(report.totalTokens),
                subtitle: '${formatAmount(report.totalTokens)} tokens',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: usageTile(
                '消费',
                costText.isEmpty ? '—' : costText,
                subtitle:
                    '请求 ${formatCompact(report.models.fold(0.0, (s, m) => s + m.requests))} 次',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.bolt, size: 15, color: scheme.primary),
            const SizedBox(width: 5),
            Text(
              '缓存命中率 $hitText',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 每日明细：接口真的返回了正数才画图，否则提示，不留空白坐标系
        if (report.days.any((d) => d.tokens > 0))
          UsageBarChart(days: report.days)
        else
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '该接口未返回每日明细数据',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// 用量概览里的双栏小卡片
  Widget usageTile(String label, String value, {String? subtitle}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.onSurface.withAlpha(10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  /// 各模型用量占比：横向条形图，一眼看出哪个模型消耗最多。
  /// 用量为 0 的模型不单独占行，折叠成一句提示。
  Widget modelShareCard(ColorScheme scheme) {
    final report = usageReport!;
    final models = List<ModelUsage>.from(report.models)
      ..sort((a, b) => b.totalTokens.compareTo(a.totalTokens));
    final total = models.fold(0.0, (sum, m) => sum + m.totalTokens);
    final usedModels = models.where((m) => m.totalTokens > 0).toList();
    final hiddenCount = models.length - usedModels.length;

    return card([
      sectionTitle('各模型用量占比'),
      const SizedBox(height: 10),
      if (usedModels.isEmpty)
        Text(
          '本月各模型均无用量',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        )
      else ...[
        for (final m in usedModels)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: modelShareRow(m, total, scheme),
          ),
        if (hiddenCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '另有 $hiddenCount 个模型本月未使用',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    ]);
  }

  Widget modelShareRow(ModelUsage model, double total, ColorScheme scheme) {
    final share = total > 0 ? (model.totalTokens / total).clamp(0.0, 1.0) : 0.0;
    final percent = (share * 100).round();

    return Row(
      children: [
        SizedBox(
          width: 118,
          child: Text(
            model.model,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share == 0 ? 0 : share,
              minHeight: 8,
              backgroundColor: scheme.onSurface.withAlpha(16),
              color: scheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$percent%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              Text(
                '${formatCompact(model.totalTokens)} tok',
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ───────────────── 4. 用量趋势 ─────────────────

  Widget trendCard(ColorScheme scheme) {
    final history = account.history;
    // 数据不足的友好提示
    Widget? hint;
    if (history.length < 5) {
      hint = Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                history.isEmpty
                    ? '还没有快照：余额每次刷新都会记录一个数据点'
                    : '数据不足，仅记录 ${history.length} 次快照，保持自动刷新可积累更多数据',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    return card([
      Row(
        children: [
          Expanded(child: sectionTitle('用量趋势')),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('柱状图')),
              ButtonSegment(value: false, label: Text('折线图')),
            ],
            selected: {isBarChart},
            onSelectionChanged: (selection) =>
                setState(() => isBarChart = selection.first),
            showSelectedIcon: false,
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (history.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text(
              '刷新余额后，这里会画出变化趋势',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
        )
      else
        TrendChart(points: history, isBarChart: isBarChart),
      ?hint,
    ]);
  }

  // ───────────────── 5. API 信息（默认折叠） ─────────────────

  Widget apiInfoCard(ColorScheme scheme) {
    final preset = presetById(account.providerId);

    return expansionCard(
      sectionKey: _apiInfoKey,
      title: 'API 信息',
      onExpansionChanged: (open) => _scrollToSection(_apiInfoKey, open),
      children: [
        infoRow('提供商', preset.label, scheme),
        infoRow('接口地址', account.balanceUrl, scheme, copyable: true),
        apiKeyRow(scheme),
        infoRow(
          '货币',
          account.currencyCode == null || account.currencyCode!.isEmpty
              ? '—'
              : '${account.currencyCode}（${account.displayUnit()}）',
          scheme,
        ),
        if (account.isValidateOnly)
          infoRow(
            'Key 校验',
            account.isKeyValid == null
                ? '未校验'
                : account.isKeyValid!
                ? '有效 · ${account.availableModels ?? 0} 个可用模型'
                : '失效',
            scheme,
          ),
        infoRow(
          '最后刷新',
          account.lastRefreshed == null
              ? '尚未刷新'
              : formatTime(account.lastRefreshed!),
          scheme,
        ),
      ],
    );
  }

  Widget infoRow(
    String label,
    String value,
    ColorScheme scheme, {
    bool copyable = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
          if (copyable)
            IconButton(
              tooltip: '复制',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () => copyText(value, '已复制'),
            ),
        ],
      ),
    );
  }

  /// API Key 行：默认打码，点眼睛切换；带复制按钮
  Widget apiKeyRow(ColorScheme scheme) {
    final key = account.apiKey;
    final masked = key.length <= 8
        ? '••••••••'
        : '${key.substring(0, 4)}••••••••${key.substring(key.length - 4)}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              'API Key',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              showApiKey ? key : masked,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: showApiKey ? '隐藏' : '显示',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              showApiKey
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 18,
            ),
            onPressed: () => setState(() => showApiKey = !showApiKey),
          ),
          IconButton(
            tooltip: '复制',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy, size: 16),
            onPressed: () => copyText(key, 'API Key 已复制'),
          ),
        ],
      ),
    );
  }

  // ───────────────── 6. 原始返回（开发者模式才显示） ─────────────────

  Widget rawResponseCard(ColorScheme scheme) {
    return expansionCard(
      sectionKey: _rawKey,
      title: '接口原始返回',
      onExpansionChanged: (open) => _scrollToSection(_rawKey, open),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.onSurface.withAlpha(10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            prettyRawJson(account.rawResponse!),
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => copyText(account.rawResponse ?? '', '已复制原始返回'),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制'),
          ),
        ),
      ],
    );
  }

  /// 折叠卡片：圆角 Material 让点击水花正确显示（并被圆角裁剪），
  /// 展开时把该区块滚动到视口顶部，内容再长也能看全。
  Widget expansionCard({
    required GlobalKey sectionKey,
    required String title,
    required List<Widget> children,
    ValueChanged<bool>? onExpansionChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: sectionKey,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            backgroundColor: Colors.transparent,
            collapsedBackgroundColor: Colors.transparent,
            title: sectionTitle(title),
            onExpansionChanged: onExpansionChanged,
            children: children,
          ),
        ),
      ),
    );
  }

  /// 展开后把区块顶部滚到视口最上方
  void _scrollToSection(GlobalKey key, bool opening) {
    if (!opening) return;
    Future.delayed(const Duration(milliseconds: 200), () {
      final sectionContext = key.currentContext;
      if (sectionContext == null || !sectionContext.mounted) return;
      Scrollable.ensureVisible(
        sectionContext,
        duration: const Duration(milliseconds: 250),
        alignment: 0.0,
      );
    });
  }

  /// 把原始返回整理成缩进格式，方便阅读；解析失败就原样显示
  String prettyRawJson(String raw) {
    try {
      return toPrettyJson(jsonDecode(raw));
    } catch (_) {
      return raw;
    }
  }
}
