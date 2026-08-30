import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../storage.dart';

/// 独立的设置页面（不再是弹窗）。
/// 每一项改动后立即生效并保存，所以没有“保存”按钮。
class SettingsPage extends StatefulWidget {
  final AppSettings settings;
  final List<ModelAccount> models; // 当前模型列表（导出数据用）
  final ValueChanged<AppSettings> onSettingsChanged;
  final ValueChanged<AppData> onDataReplaced; // 导入 / 清空数据时回调

  const SettingsPage({
    super.key,
    required this.settings,
    required this.models,
    required this.onSettingsChanged,
    required this.onDataReplaced,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // 页面内部保存一份当前设置，改动时更新自己并上抛
  late AppSettings current = widget.settings;
  String dataPath = '读取中…';

  @override
  void initState() {
    super.initState();
    // 展示数据文件的保存位置，方便用户备份
    dataFilePath().then((path) {
      if (mounted) setState(() => dataPath = path);
    });
  }

  void apply(AppSettings newSettings) {
    setState(() => current = newSettings);
    widget.onSettingsChanged(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ─────────── 刷新 ───────────
          sectionTitle('刷新'),
          sectionCard([
            SwitchListTile(
              title: const Text('打开应用时自动刷新'),
              subtitle: const Text('启动后自动查询所有账号的余额与用量'),
              value: current.autoRefreshOnStart,
              onChanged: (value) =>
                  apply(current.copyWith(autoRefreshOnStart: value)),
            ),
            ListTile(
              title: const Text('定时自动刷新'),
              subtitle: const Text('按固定间隔在后台重新查询'),
              trailing: DropdownButton<int>(
                value: current.autoRefreshMinutes,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('不自动')),
                  DropdownMenuItem(value: 1, child: Text('每 1 分钟')),
                  DropdownMenuItem(value: 5, child: Text('每 5 分钟')),
                  DropdownMenuItem(value: 15, child: Text('每 15 分钟')),
                  DropdownMenuItem(value: 30, child: Text('每 30 分钟')),
                  DropdownMenuItem(value: 60, child: Text('每 60 分钟')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    apply(current.copyWith(autoRefreshMinutes: value));
                  }
                },
              ),
            ),
            ListTile(
              title: const Text('请求超时时间'),
              trailing: DropdownButton<int>(
                value: current.timeoutSeconds,
                items: const [
                  DropdownMenuItem(value: 5, child: Text('5 秒')),
                  DropdownMenuItem(value: 10, child: Text('10 秒')),
                  DropdownMenuItem(value: 15, child: Text('15 秒')),
                  DropdownMenuItem(value: 30, child: Text('30 秒')),
                  DropdownMenuItem(value: 60, child: Text('60 秒')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    apply(current.copyWith(timeoutSeconds: value));
                  }
                },
              ),
            ),
          ]),

          // ─────────── API 网络 ───────────
          sectionTitle('API 网络'),
          sectionCard([
            ListTile(
              title: const Text('网络代理'),
              subtitle: Text(
                current.proxyModeName == 'manual'
                    ? '手动代理：${current.proxyAddress.isEmpty ? '未填写地址' : current.proxyAddress}'
                    : proxyModeLabel(current.proxyModeName),
              ),
              trailing: DropdownButton<String>(
                value: current.proxyModeName,
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('直连')),
                  DropdownMenuItem(value: 'system', child: Text('跟随环境变量')),
                  DropdownMenuItem(value: 'manual', child: Text('手动代理')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    apply(current.copyWith(proxyModeName: value));
                  }
                },
              ),
            ),
            if (current.proxyModeName == 'manual')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: TextEditingController(text: current.proxyAddress),
                  decoration: const InputDecoration(
                    labelText: '代理地址',
                    hintText: '例如 127.0.0.1:7890',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) =>
                      apply(current.copyWith(proxyAddress: value)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '访问 OpenRouter、Z.ai 等海外接口速度慢时，可以配置 HTTP 代理。',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ]),

          // ─────────── 数据管理 ───────────
          sectionTitle('数据管理'),
          sectionCard([
            ListTile(
              leading: const Icon(Icons.upload_outlined),
              title: const Text('导出数据'),
              subtitle: const Text('把全部数据（含 API Key）复制到剪贴板'),
              onTap: exportToClipboard,
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('从剪贴板导入'),
              subtitle: const Text('粘贴之前导出的数据，覆盖当前全部内容'),
              onTap: importFromClipboard,
            ),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
              title: Text('清空全部数据',
                  style: TextStyle(color: scheme.error)),
              onTap: confirmClearAll,
            ),
          ]),

          // ─────────── 开发者 ───────────
          sectionTitle('开发者'),
          sectionCard([
            SwitchListTile(
              title: const Text('开发者模式'),
              subtitle: const Text('在模型详情页显示接口原始返回（JSON）'),
              value: current.developerMode,
              onChanged: (value) => apply(current.copyWith(developerMode: value)),
            ),
          ]),

          // ─────────── 外观 ───────────
          sectionTitle('外观'),
          sectionCard([
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('主题色',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Wrap(
                spacing: 10,
                children: [
                  for (final entry in seedColors.entries)
                    colorDot(entry.key, entry.value),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text('深色模式',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'system',
                      label: Text('跟随系统'),
                      icon: Icon(Icons.brightness_auto_outlined)),
                  ButtonSegment(
                      value: 'light',
                      label: Text('浅色'),
                      icon: Icon(Icons.light_mode_outlined)),
                  ButtonSegment(
                      value: 'dark',
                      label: Text('深色'),
                      icon: Icon(Icons.dark_mode_outlined)),
                ],
                selected: {current.themeModeName},
                onSelectionChanged: (selection) =>
                    apply(current.copyWith(themeModeName: selection.first)),
              ),
            ),
          ]),

          // ─────────── 数据文件位置 ───────────
          const SizedBox(height: 8),
          Text(
            '数据文件：$dataPath',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  String proxyModeLabel(String name) {
    if (name == 'system') return '跟随环境变量';
    if (name == 'manual') return '手动代理';
    return '直连';
  }

  Widget sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }

  /// 把一组设置项包在圆角卡片里
  Widget sectionCard(List<Widget> children) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  /// 一个可选的主题色圆点，选中的带勾
  Widget colorDot(String name, Color color) {
    final selected = current.seedColorName == name;
    return Tooltip(
      message: name,
      child: InkWell(
        onTap: () => apply(current.copyWith(seedColorName: name)),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 20)
              : null,
        ),
      ),
    );
  }

  // ─────────── 数据管理操作 ───────────

  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 导出：把全部数据变成 JSON 文本放到剪贴板
  Future<void> exportToClipboard() async {
    final data = AppData(models: List.of(widget.models), settings: current);
    await Clipboard.setData(ClipboardData(text: toPrettyJson(data.toJson())));
    if (!mounted) return;
    showSnackBar('已导出到剪贴板（${data.models.length} 个模型）');
  }

  /// 导入：从剪贴板读取 JSON 并整体替换
  Future<void> importFromClipboard() async {
    final confirmed = await confirmDialog(
      '从剪贴板导入',
      '导入会覆盖当前的模型列表和设置，确定继续吗？',
      confirmText: '导入',
    );
    if (confirmed == null || !confirmed) return;

    final text = await Clipboard.getData('text/plain');
    final content = text?.text?.trim() ?? '';
    if (content.isEmpty) {
      showSnackBar('剪贴板是空的', isError: true);
      return;
    }

    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic> || !decoded.containsKey('models')) {
        throw Exception('格式不对');
      }
      final models = <ModelAccount>[];
      final modelList = decoded['models'];
      if (modelList is List) {
        for (final item in modelList) {
          if (item is Map<String, dynamic>) {
            models.add(ModelAccount.fromJson(item));
          }
        }
      }
      final settingsJson = decoded['settings'];
      final settings = settingsJson is Map<String, dynamic>
          ? AppSettings.fromJson(settingsJson)
          : AppSettings.defaults();

      widget.onDataReplaced(AppData(models: models, settings: settings));
      if (!mounted) return;
      showSnackBar('导入成功（${models.length} 个模型）');
    } catch (_) {
      showSnackBar('导入失败：剪贴板内容不是有效的 TokenMeow 数据', isError: true);
    }
  }

  /// 清空全部数据，需要二次确认
  Future<void> confirmClearAll() async {
    final confirmed = await confirmDialog(
      '清空全部数据',
      '所有模型和设置都会被删除，且无法恢复。确定继续吗？',
      confirmText: '清空',
      destructive: true,
    );
    if (confirmed == null || !confirmed) return;
    widget.onDataReplaced(AppData.empty());
    if (!mounted) return;
    showSnackBar('已清空全部数据');
  }

  Future<bool?> confirmDialog(
    String title,
    String content, {
    required String confirmText,
    bool destructive = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }
}
