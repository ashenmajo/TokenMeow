import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets/provider_badge.dart';

/// 去掉首尾空格；全是空格就返回 null（对应“可选字段不填”的情况）
String? trimOrNull(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// 添加 / 编辑模型的弹窗。existing 不为空表示编辑。
/// 点“保存”后把填好的 ModelAccount 传回主页面，这里不做保存操作。
///
/// 预设提供商的“余额接口地址”由提供商自动推断，不显示输入框；
/// 只有选“自定义”时才需要用户自己填地址和 JSON 路径。
class AddModelDialog extends StatefulWidget {
  final ModelAccount? existing;

  const AddModelDialog({super.key, this.existing});

  @override
  State<AddModelDialog> createState() => _AddModelDialogState();
}

class _AddModelDialogState extends State<AddModelDialog> {
  final _formKey = GlobalKey<FormState>();
  late String providerId;
  late final TextEditingController nameController;
  late final TextEditingController urlController;
  late final TextEditingController keyController;
  late final TextEditingController unitController;
  late final TextEditingController pathRemainingController;
  late final TextEditingController pathUsedController;
  late final TextEditingController pathTotalController;
  late final TextEditingController pathCurrencyController;
  late final TextEditingController pathDetailsController;
  late final TextEditingController usageAmountUrlController;
  late final TextEditingController usageCostUrlController;
  late final TextEditingController keyCheckUrlController;
  bool obscureKey = true; // 是否隐藏 API Key 的明文

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    providerId = existing?.providerId ?? 'deepseek';
    final preset = presetById(providerId);
    // 名称默认用提供商短名，用户可随时改（比如“DeepSeek 主号”）
    nameController = TextEditingController(
      text: existing?.name ?? preset.shortLabel,
    );
    urlController = TextEditingController(
      text: existing?.balanceUrl ?? preset.balanceUrl,
    );
    keyController = TextEditingController(text: existing?.apiKey ?? '');
    unitController = TextEditingController(text: existing?.unit ?? preset.unit);
    // 路径类字段：模型上保存过的优先，否则用预设默认值
    pathRemainingController = TextEditingController(
      text: existing?.pathRemaining ?? preset.pathRemaining,
    );
    pathUsedController = TextEditingController(
      text: existing?.pathUsed ?? preset.pathUsed,
    );
    pathTotalController = TextEditingController(
      text: existing?.pathTotal ?? preset.pathTotal,
    );
    pathCurrencyController = TextEditingController(
      text: existing?.pathCurrency ?? preset.pathCurrency,
    );
    pathDetailsController = TextEditingController(
      text: existing?.pathDetails ?? preset.pathDetails,
    );
    usageAmountUrlController = TextEditingController(
      text: existing?.usageAmountUrl ?? preset.usageAmountUrl,
    );
    usageCostUrlController = TextEditingController(
      text: existing?.usageCostUrl ?? preset.usageCostUrl,
    );
    keyCheckUrlController = TextEditingController(
      text: existing?.keyCheckUrl ?? preset.keyCheckUrl,
    );
  }

  @override
  void dispose() {
    // 用完的控制器要释放，避免内存泄漏
    nameController.dispose();
    urlController.dispose();
    keyController.dispose();
    unitController.dispose();
    pathRemainingController.dispose();
    pathUsedController.dispose();
    pathTotalController.dispose();
    pathCurrencyController.dispose();
    pathDetailsController.dispose();
    usageAmountUrlController.dispose();
    usageCostUrlController.dispose();
    keyCheckUrlController.dispose();
    super.dispose();
  }

  /// 切换提供商：接口地址、单位、JSON 路径都自动换成新提供商预设的值。
  /// 名称还是空的、或者还是上一个提供商的默认名，就一并换成新提供商的短名。
  void onProviderChanged(String newId) {
    final preset = presetById(newId);
    final oldName = nameController.text.trim();
    final isDefaultName =
        oldName.isEmpty || oldName == presetById(providerId).shortLabel;
    if (isDefaultName) {
      nameController.text = preset.shortLabel;
    }
    setState(() {
      providerId = newId;
      urlController.text = preset.balanceUrl;
      unitController.text = preset.unit;
      pathRemainingController.text = preset.pathRemaining;
      pathUsedController.text = preset.pathUsed;
      pathTotalController.text = preset.pathTotal;
      pathCurrencyController.text = preset.pathCurrency;
      pathDetailsController.text = preset.pathDetails;
      usageAmountUrlController.text = preset.usageAmountUrl;
      usageCostUrlController.text = preset.usageCostUrl;
      keyCheckUrlController.text = preset.keyCheckUrl;
    });
  }

  /// 点击“保存”：检查表单，通过就把结果传回主页面
  void save() {
    if (!_formKey.currentState!.validate()) return;

    final isCustom = providerId == 'custom';
    final account = ModelAccount(
      id:
          widget.existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: nameController.text.trim(),
      providerId: providerId,
      // 预设提供商的地址直接用预设的，只有自定义才用输入框里的
      balanceUrl: isCustom
          ? urlController.text.trim()
          : presetById(providerId).balanceUrl,
      apiKey: keyController.text.trim(),
      unit: unitController.text.trim(),
      // JSON 路径只有自定义才保存（预设的走预设默认值，改了也能对上号）
      pathCurrency: trimOrNull(pathCurrencyController.text) ?? '',
      pathDetails: pathDetailsController.text.trim(),
      // 用量 Token 在详情页里填写，编辑时原样保留
      usageToken: widget.existing?.usageToken ?? '',
      usageAmountUrl: trimOrNull(usageAmountUrlController.text) ?? '',
      usageCostUrl: trimOrNull(usageCostUrlController.text) ?? '',
      keyCheckUrl: trimOrNull(keyCheckUrlController.text) ?? '',
      // 预设提供商的高级路径也可以覆盖保存（有内容才存）
      pathRemaining: trimOrNull(pathRemainingController.text),
      pathUsed: trimOrNull(pathUsedController.text),
      pathTotal: trimOrNull(pathTotalController.text),
    );
    Navigator.pop(context, account);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preset = presetById(providerId);
    final isCustom = providerId == 'custom';

    return AlertDialog(
      title: Text(widget.existing == null ? '添加账号' : '编辑账号'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildLabel('账号名称'),
                TextFormField(
                  controller: nameController,
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请填写账号名称' : null,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: '例如：DeepSeek 主号'),
                ),
                buildLabel('提供商'),
                DropdownButtonFormField<String>(
                  initialValue: providerId,
                  isExpanded: true,
                  dropdownColor: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  icon: const Icon(Icons.unfold_more, size: 18),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest.withAlpha(90),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: [
                    for (final p in providerPresets)
                      DropdownMenuItem(
                        value: p.id,
                        child: Row(
                          children: [
                            ProviderBadge(preset: p, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                p.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) onProviderChanged(value);
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  preset.hint,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                buildLabel('余额接口地址'),
                if (isCustom) ...[
                  // 自定义：需要自己填
                  TextFormField(
                    controller: urlController,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    validator: validateUrl,
                    decoration: const InputDecoration(hintText: 'https://…'),
                  ),
                ] else if (preset.balanceUrl.isEmpty) ...[
                  // 无余额接口的提供商（OpenAI / Claude / Gemini 等）
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '该提供商不提供余额查询接口：账号用于校验 Key（可用模型数），'
                          '余额可在详情页手动记录。',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // 预设提供商：地址自动推断，只展示不允许改
                  Row(
                    children: [
                      Icon(Icons.link, size: 16, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          preset.balanceUrl,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        '自动填充',
                        style: TextStyle(fontSize: 12, color: scheme.primary),
                      ),
                    ],
                  ),
                ],
                buildLabel('API Key'),
                TextFormField(
                  controller: keyController,
                  obscureText: obscureKey,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '请填写 API Key'
                      : null,
                  decoration: InputDecoration(
                    hintText: 'sk-…',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureKey
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => setState(() => obscureKey = !obscureKey),
                    ),
                  ),
                ),
                buildLabel('单位（可选）'),
                TextFormField(
                  controller: unitController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: '留空则按接口返回的货币自动显示（如 CNY → ¥）',
                  ),
                ),
                if (isCustom) ...[
                  buildLabel('剩余量的 JSON 路径'),
                  TextFormField(
                    controller: pathRemainingController,
                    decoration: const InputDecoration(
                      hintText: '例如：data.balance（多个候选用英文逗号分隔）',
                    ),
                  ),
                  buildLabel('已使用的 JSON 路径（可选）'),
                  TextFormField(
                    controller: pathUsedController,
                    decoration: const InputDecoration(hintText: '例如：data.used'),
                  ),
                  buildLabel('总额度的 JSON 路径（可选）'),
                  TextFormField(
                    controller: pathTotalController,
                    decoration: const InputDecoration(
                      hintText: '例如：data.total',
                    ),
                  ),
                  buildLabel('货币代码的 JSON 路径（可选）'),
                  TextFormField(
                    controller: pathCurrencyController,
                    decoration: const InputDecoration(
                      hintText: '例如：data.currency，取到 CNY 会自动显示 ¥',
                    ),
                  ),
                  buildLabel('明细字段（可选，每行一条：显示名=JSON路径）'),
                  TextFormField(
                    controller: pathDetailsController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: '例如：\n赠送额度=data.granted\n充值余额=data.toppedUp',
                    ),
                  ),
                  buildLabel('用量接口地址（可选，DeepSeek 平台格式）'),
                  TextFormField(
                    controller: usageAmountUrlController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: '…/usage/amount?month={month}&year={year}',
                    ),
                  ),
                  buildLabel('消费接口地址（可选）'),
                  TextFormField(
                    controller: usageCostUrlController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: '…/usage/cost?month={month}&year={year}',
                    ),
                  ),
                  buildLabel('Key 校验接口（可选）'),
                  TextFormField(
                    controller: keyCheckUrlController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: '例如 https://中转站.com/v1/models',
                    ),
                  ),
                  Text(
                    '用量接口返回结构需与 DeepSeek 平台一致；网页 Token 在详情页的“本月用量”里填写。',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: save, child: const Text('保存')),
      ],
    );
  }

  Widget buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  String? validateUrl(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '请填写余额接口地址';
    final uri = Uri.tryParse(text);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return '地址要以 http:// 或 https:// 开头';
    }
    return null;
  }
}
