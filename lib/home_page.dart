import 'dart:async';

import 'package:flutter/material.dart';

import 'api_service.dart';
import 'models.dart';
import 'pages/model_detail_page.dart';
import 'pages/settings_page.dart';
import 'usage_service.dart';
import 'utils.dart';
import 'widgets/about_dialog.dart';
import 'widgets/add_model_dialog.dart';
import 'widgets/model_card.dart';

/// 主页面：标题栏（软件名 + 三点菜单）+ 内容区（模型卡片）+ 右下角添加按钮
class HomePage extends StatefulWidget {
  final List<ModelAccount> models;
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;
  final ValueChanged<List<ModelAccount>> onModelsChanged;
  final ValueChanged<AppData> onDataReplaced; // 设置页导入/清空数据时回调

  const HomePage({
    super.key,
    required this.models,
    required this.settings,
    required this.onSettingsChanged,
    required this.onModelsChanged,
    required this.onDataReplaced,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? autoRefreshTimer; // 定时自动刷新用的计时器
  String searchQuery = '';
  List<ModelAccount> get filteredModels {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return widget.models;

    return widget.models.where((account) {
      final preset = presetById(account.providerId);

      return [
        account.name,
        account.providerId,
        preset.label,
        preset.shortLabel,
        account.maskedKey,
        account.statusLabel,
      ].any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    // 首次进入时按设置决定要不要自动刷新一遍（只在进入时触发一次）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.settings.autoRefreshOnStart) {
        refreshAll();
      }
    });
    setupAutoRefreshTimer();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 设置变了的话，重新安排定时刷新
    if (oldWidget.settings.autoRefreshMinutes !=
        widget.settings.autoRefreshMinutes) {
      setupAutoRefreshTimer();
    }
  }

  @override
  void dispose() {
    autoRefreshTimer?.cancel();
    super.dispose();
  }

  /// 按设置的间隔启动/取消定时刷新
  void setupAutoRefreshTimer() {
    autoRefreshTimer?.cancel();
    final minutes = widget.settings.autoRefreshMinutes;
    if (minutes > 0) {
      autoRefreshTimer = Timer.periodic(Duration(minutes: minutes), (_) {
        refreshAll();
      });
    }
  }

  // ─────────────────────────── 数据操作 ───────────────────────────

  /// 刷新所有模型（正在查询中的会跳过）
  Future<void> refreshAll() async {
    final futures = <Future<void>>[];
    for (final account in widget.models) {
      futures.add(refreshOne(account));
    }
    await Future.wait(futures);
  }

  /// 刷新单个账号：查询余额（或校验 Key）→ 把结果写回账号对象 → 通知外层保存
  Future<void> refreshOne(ModelAccount account) async {
    if (account.isLoading) return;
    setState(() {
      account.isLoading = true;
      account.errorMessage = null;
    });

    BalanceResult? result;
    String? error;
    if (account.isValidateOnly) {
      // 没有余额接口的提供商（OpenAI 等）：只校验 Key，
      // 结果直接反映在状态标签上（Key 有效 / Key 失效）
      try {
        final check = await validateApiKey(account, settings: widget.settings);
        account.isKeyValid = check.valid;
        account.availableModels = check.modelCount;
      } catch (e) {
        error = friendlyError(e);
      }
    } else {
      try {
        result = await fetchBalance(account, settings: widget.settings);
      } catch (e) {
        error = friendlyError(e);
      }
    }

    if (!mounted) return;
    setState(() {
      account.isLoading = false;
      if (account.isValidateOnly) {
        // 仅校验型：校验成功就清掉错误提示，Key 状态交给状态标签表达
        if (error == null) {
          account.errorMessage = null;
          account.lastRefreshed = DateTime.now();
        } else {
          account.errorMessage = error;
        }
      } else if (result != null) {
        account.remaining = result.remaining;
        account.used = result.used;
        account.total = result.total;
        account.details = result.details;
        account.currencyCode = result.currencyCode;
        account.isAvailable = result.isAvailable;
        account.rawResponse = result.rawJson;
        account.lastRefreshed = DateTime.now();
        account.appendHistory(); // 记录历史，详情页画趋势图用
      } else {
        account.errorMessage = error;
      }
    });

    // 配置了用量接口且填了 Token：顺手把本月用量摘要也刷新（失败静默跳过，
    // 具体原因在详情页的用量概览里能看到）
    if (account.hasUsageApi && account.usageToken.trim().isNotEmpty) {
      try {
        final now = DateTime.now();
        final report = await fetchUsage(
          account,
          widget.settings,
          year: now.year,
          month: now.month,
        );
        account.recordUsageSummary(
          tokens: report.totalTokens,
          cost: report.totalCost,
          cacheHitRate: report.cacheHitRate,
          year: now.year,
          month: now.month,
        );
      } catch (_) {
        // 静默跳过
      }
    }

    // 把查询结果和“最后刷新时间”等变化保存下来
    widget.onModelsChanged(widget.models);
  }

  /// 打开“添加 / 编辑模型”弹窗。existing 不为空表示编辑。
  Future<void> openAddOrEditDialog({ModelAccount? existing}) async {
    final result = await showDialog<ModelAccount>(
      context: context,
      builder: (context) => AddModelDialog(existing: existing),
    );
    if (result == null || !mounted) return;

    if (existing == null) {
      // 新增：放到列表最前面，并立刻查询一次
      setState(() => widget.models.insert(0, result));
      widget.onModelsChanged(widget.models);
      refreshOne(result);
      showSnackBar('已添加账号「${result.name}」');
    } else {
      // 编辑：按 id 找到旧的位置替换掉
      final index = widget.models.indexWhere((m) => m.id == result.id);
      if (index != -1) {
        setState(() => widget.models[index] = result);
      }
      widget.onModelsChanged(widget.models);
      refreshOne(result);
      showSnackBar('已保存账号「${result.name}」');
    }
  }

  /// 删除前先确认一下
  Future<void> confirmDelete(
    ModelAccount account, {
    VoidCallback? onDeleted,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确定要删除「${account.name}」吗？删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => widget.models.remove(account));
    widget.onModelsChanged(widget.models);
    onDeleted?.call();
    showSnackBar('已删除账号「${account.name}」');
  }

  /// 点击卡片 → 详情页
  void openDetailPage(ModelAccount account) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ModelDetailPage(
          account: account,
          settings: widget.settings,
          onChanged: () => widget.onModelsChanged(widget.models),
          onDeleteRequested: () => confirmDelete(
            account,
            onDeleted: () {
              // 删除后把详情页也关掉
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
    );
  }

  // ─────────────────────────── 弹窗 / 页面 ───────────────────────────

  /// 打开独立的设置页面
  void openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          settings: widget.settings,
          models: widget.models,
          onSettingsChanged: widget.onSettingsChanged,
          onDataReplaced: (newData) {
            widget.onDataReplaced(newData);
            // 数据被替换后，按新设置重新安排定时刷新并刷新一遍
            setupAutoRefreshTimer();
            if (newData.settings.autoRefreshOnStart) refreshAll();
          },
        ),
      ),
    );
  }

  void openAbout() {
    showDialog(context: context, builder: (context) => const AboutAppDialog());
  }

  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ─────────────────────────── 界面 ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(context),
      body: buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => openAddOrEditDialog(),
        tooltip: '添加账号',
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 标题栏：左边是软件名，右边是刷新按钮 + 竖向三点菜单
  PreferredSizeWidget buildAppBar(BuildContext context) {
    return AppBar(
      centerTitle: false,
      title: Row(
        children: [
          const Text(
            'TokenMeow',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          const SizedBox(width: 30),
          Expanded(
            child: SizedBox(
              height: 40,
              child: SearchBar(
                leading: Icon(Icons.search),
                hintText: '搜索',
                elevation: WidgetStateProperty.all(0),
                onChanged: (value) {
                  setState(() {
                    searchQuery = value;
                  });
                },
              ),
            ),
          ),
        ],
      ),

      actions: [
        PopupMenuButton<String>(
          tooltip: '更多选项',
          onSelected: (value) {
            if (value == 'settings') openSettings();
            if (value == 'about') openAbout();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'settings',
              child: Row(
                children: [
                  Icon(Icons.settings_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('设置'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'about',
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20),
                  SizedBox(width: 12),
                  Text('关于'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget buildBody() {
    if (widget.models.isEmpty) {
      return buildEmptyView();
    }
    if (filteredModels.isEmpty) {
      return const Center(child: Text('没有匹配的账号'));
    }
    // 手机上可以下拉刷新
    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: refreshAll,
      child: buildModelGrid(filteredModels),
    );
  }

  /// 一个模型都没有时的引导页
  Widget buildEmptyView() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text('还没有添加账号', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '点击右下角的“添加账号”，把你的 API Key\n和接口地址填进来，就能集中查看剩余额度了。',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  /// 模型卡片列表（自适应高度）：按可用宽度算出列数（1~3 列），
  /// 每行卡片等高（取该行最高的那张），屏幕特别宽时整体限宽居中。
  Widget buildModelGrid(List<ModelAccount> models) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth > 1280
            ? 1280.0
            : constraints.maxWidth;
        const gap = 12.0;
        final usable = contentWidth - 32; // 左右各 16 的内边距
        final columns = (usable / 442).floor().clamp(1, 3);
        final cardWidth = (usable - gap * (columns - 1)) / columns;

        // 按列数把账号切行
        final rows = <List<ModelAccount>>[];
        for (final account in models) {
          if (rows.isEmpty || rows.last.length == columns) {
            rows.add([account]); // 开新行
          } else {
            rows.last.add(account); // 塞进当前行
          }
        }

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            child: Column(
              children: [
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: gap),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final account in row)
                            SizedBox(
                              width: cardWidth,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: identical(account, row.last) ? 0 : gap,
                                ),
                                child: ModelCard(
                                  account: account,
                                  onOpen: () => openDetailPage(account),
                                  onRefresh: () => refreshOne(account),
                                  onEdit: () =>
                                      openAddOrEditDialog(existing: account),
                                  onDelete: () => confirmDelete(account),
                                ),
                              ),
                            ),
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.3,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
