import 'dart:convert';

import 'package:flutter/material.dart' show Color, ThemeMode;

/// 一个“模型账号”，代表用户添加的一条 API 信息。
/// 比如你在 DeepSeek 有个账号里还有余额，就把它加进来统一查看。
class ModelAccount {
  String id; // 唯一标识，用创建时间生成
  String name; // 显示名称，例如 “DeepSeek V4 Pro”
  String providerId; // 提供商 id，对应 providerPresets 里的 id
  String balanceUrl; // 余额查询接口的完整地址（预设提供商自动带出）
  String apiKey; // API 密钥
  String unit; // 手动指定的单位符号；留空则按接口返回的货币自动显示
  String pathCurrency; // 货币代码（CNY/USD…）的 JSON 路径，多个候选用英文逗号分隔
  String pathDetails; // 明细字段，多行文本，每行 “显示名=JSON路径”
  String? pathRemaining; // 剩余量路径（覆盖预设默认值；自定义接口时填写）
  String? pathUsed; // 已使用路径
  String? pathTotal; // 总额度路径

  // ── 用量查询（目前 DeepSeek 平台支持，一期为手动粘贴的网页 Token） ──
  String usageToken = ''; // 网页登录 Token（短期有效，失效后要重新获取）
  String usageAmountUrl = ''; // 用量接口地址模板，{month}/{year} 占位；留空用预设的
  String usageCostUrl = ''; // 消费接口地址模板（可选）；留空用预设的
  String keyCheckUrl = ''; // Key 校验接口地址；留空用预设的（中转站用户填自己的）

  // ── 最近一次用量查询的摘要（存在文件里，首页卡片可以直接显示） ──
  double? usageMonthTokens; // 当月总 Token
  double? usageMonthCost; // 当月消费金额
  String? usageMonthLabel; // 数据属于哪个月，例如 “2026-08”
  double? usageMonthCacheHitRate; // 当月缓存命中率（0 ~ 1）

  // ── 余额状态相关（查询结果，不存文件） ──
  bool? isAvailable; // 接口返回的可用标志（DeepSeek 有，false 表示已过期/停用）
  bool? isKeyValid; // 仅校验型账号：Key 是否有效
  int? availableModels; // Key 校验时返回的可用模型数

  // ── 下面是查询结果，remaining/used/total/details 等只在内存里，
  //    history 和 rawResponse 会保存，供详情页画趋势图、查看原始返回 ──
  double? remaining; // 剩余量
  double? used; // 已使用
  double? total; // 总额度
  Map<String, double> details = {}; // 其他明细字段（赠送额度、充值余额等）
  String? currencyCode; // 接口返回的货币代码，如 CNY、USD
  String? errorMessage; // 查询失败的原因
  bool isLoading = false; // 是否正在查询
  DateTime? lastRefreshed; // 最后一次成功查询的时间
  String? rawResponse; // 最近一次接口的原始 JSON 文本
  List<HistoryPoint> history = []; // 历史查询记录（画趋势图用）

  ModelAccount({
    required this.id,
    required this.name,
    required this.providerId,
    required this.balanceUrl,
    required this.apiKey,
    required this.unit,
    this.pathCurrency = '',
    this.pathDetails = '',
    this.pathRemaining,
    this.pathUsed,
    this.pathTotal,
    this.usageToken = '',
    this.usageAmountUrl = '',
    this.usageCostUrl = '',
    this.keyCheckUrl = '',
  });

  /// 保存到 JSON 文件时用到（查询结果不保存，但历史记录和原始返回要保存）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'providerId': providerId,
      'balanceUrl': balanceUrl,
      'apiKey': apiKey,
      'unit': unit,
      'pathCurrency': pathCurrency,
      'pathDetails': pathDetails,
      'pathRemaining': pathRemaining,
      'pathUsed': pathUsed,
      'pathTotal': pathTotal,
      'usageToken': usageToken,
      'usageAmountUrl': usageAmountUrl,
      'usageCostUrl': usageCostUrl,
      'keyCheckUrl': keyCheckUrl,
      'usageMonthTokens': usageMonthTokens,
      'usageMonthCost': usageMonthCost,
      'usageMonthLabel': usageMonthLabel,
      'usageMonthCacheHitRate': usageMonthCacheHitRate,
      'lastRefreshed': lastRefreshed?.toIso8601String(),
      'rawResponse': rawResponse,
      'history': history.map((h) => h.toJson()).toList(),
    };
  }

  /// 从 JSON 文件读回来时用到
  factory ModelAccount.fromJson(Map<String, dynamic> json) {
    final account = ModelAccount(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名模型',
      providerId: json['providerId'] as String? ?? 'custom',
      balanceUrl: json['balanceUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      unit: json['unit'] as String? ?? '',
      pathCurrency: json['pathCurrency'] as String? ?? '',
      pathDetails: json['pathDetails'] as String? ?? '',
      pathRemaining: json['pathRemaining'] as String?,
      pathUsed: json['pathUsed'] as String?,
      pathTotal: json['pathTotal'] as String?,
      usageToken: json['usageToken'] as String? ?? '',
      usageAmountUrl: json['usageAmountUrl'] as String? ?? '',
      usageCostUrl: json['usageCostUrl'] as String? ?? '',
      keyCheckUrl: json['keyCheckUrl'] as String? ?? '',
    );
    final refreshed = json['lastRefreshed'];
    if (refreshed is String) {
      account.lastRefreshed = DateTime.tryParse(refreshed);
    }
    if (json['rawResponse'] is String) {
      account.rawResponse = json['rawResponse'] as String;
    }
    account.usageMonthTokens = (json['usageMonthTokens'] as num?)?.toDouble();
    account.usageMonthCost = (json['usageMonthCost'] as num?)?.toDouble();
    account.usageMonthLabel = json['usageMonthLabel'] as String?;
    account.usageMonthCacheHitRate =
        (json['usageMonthCacheHitRate'] as num?)?.toDouble();
    final historyList = json['history'];
    if (historyList is List) {
      for (final item in historyList) {
        if (item is Map<String, dynamic>) {
          account.history.add(HistoryPoint.fromJson(item));
        }
      }
    }
    return account;
  }

  /// 掩码后的 API Key：前 6 位 + **** + 后 4 位（太短的 Key 返回空），
  /// 用来在界面上区分同一提供商的多个账号，又不泄露完整 Key。
  String get maskedKey {
    final key = apiKey.trim();
    if (key.length < 10) return '';
    return '${key.substring(0, 6)}****${key.substring(key.length - 4)}';
  }

  /// 显示单位：手填的 unit 优先，否则按接口返回的货币代码自动映射（CNY → ¥）
  String displayUnit() {
    final manual = unit.trim();
    if (manual.isNotEmpty) return manual;
    return currencySymbolOf(currencyCode);
  }

  /// 实际生效的用量接口地址：自己填过的优先，否则用提供商预设的
  String get effectiveUsageAmountUrl {
    final own = usageAmountUrl.trim();
    if (own.isNotEmpty) return own;
    return presetById(providerId).usageAmountUrl;
  }

  String get effectiveUsageCostUrl {
    final own = usageCostUrl.trim();
    if (own.isNotEmpty) return own;
    return presetById(providerId).usageCostUrl;
  }

  /// 是否配置了用量查询能力（有用量接口地址才显示用量卡片）
  bool get hasUsageApi => effectiveUsageAmountUrl.isNotEmpty;

  /// 追加一条历史记录，最多保留 300 条，防止文件越来越大
  void appendHistory() {
    history.add(HistoryPoint(
      time: DateTime.now(),
      remaining: remaining,
      used: used,
      total: total,
    ));
    if (history.length > 300) {
      history.removeRange(0, history.length - 300);
    }
  }

  /// 进度条里“已用”所占的比例（0 ~ 1）。
  /// 必须知道总额度才算得出：优先用 used，没有 used 就用 total - remaining 反推。
  /// 算不出（比如接口只给个余额、没有总额概念）返回 null，界面就不画进度条。
  double? usedRatio() {
    if (total == null || total! <= 0) return null;
    double? usedAmount;
    if (used != null) {
      usedAmount = used;
    } else if (remaining != null) {
      usedAmount = total! - remaining!;
    }
    if (usedAmount == null) return null;
    final ratio = usedAmount / total!;
    if (ratio < 0) return 0;
    if (ratio > 1) return 1;
    return ratio;
  }

  /// 把一次用量查询结果记到摘要字段里（首页卡片显示用）
  void recordUsageSummary({
    required double tokens,
    double? cost,
    double? cacheHitRate,
    required int year,
    required int month,
  }) {
    usageMonthTokens = tokens;
    usageMonthCost = cost;
    usageMonthLabel = '$year-${month.toString().padLeft(2, '0')}';
    usageMonthCacheHitRate = cacheHitRate;
  }

  /// 是否是“仅校验型”账号：提供商没给余额接口（OpenAI 等），
  /// 只能校验 Key、手动记录余额。
  bool get isValidateOnly {
    if (balanceUrl.trim().isNotEmpty) return false;
    return presetById(providerId).balanceUrl.isEmpty;
  }

  /// 实际生效的 Key 校验地址：自己填过的优先，否则用提供商预设的
  String get effectiveKeyCheckUrl {
    final own = keyCheckUrl.trim();
    if (own.isNotEmpty) return own;
    return presetById(providerId).keyCheckUrl;
  }

  /// 余额状态：决定状态标签显示什么
  AccountStatus get status {
    // 查询失败且没有历史数据：显示“查询失败”
    if (errorMessage != null && remaining == null) return AccountStatus.error;
    // 仅校验型账号：用 Key 校验结果当状态
    if (isValidateOnly && remaining == null) {
      if (isKeyValid == true) return AccountStatus.keyValid;
      if (isKeyValid == false) return AccountStatus.keyInvalid;
      return AccountStatus.normal; // 还没校验过，不显示标签
    }
    // 接口明确说不可用（DeepSeek 的 is_available = false）
    if (isAvailable == false) return AccountStatus.expired;
    if (remaining == null) return AccountStatus.normal;
    // 余额用光
    if (remaining! <= 0) return AccountStatus.exhausted;
    // 已用超过 80%：余额不足
    final ratio = usedRatio();
    if (ratio != null && ratio >= 0.8) return AccountStatus.low;
    return AccountStatus.normal;
  }

  String get statusLabel {
    if (status == AccountStatus.normal) return '正常';
    if (status == AccountStatus.low) return '余额不足';
    if (status == AccountStatus.exhausted) return '已用尽';
    if (status == AccountStatus.expired) return '已过期';
    if (status == AccountStatus.keyValid) return 'Key 有效';
    if (status == AccountStatus.keyInvalid) return 'Key 失效';
    return '查询失败';
  }

  Color get statusColor {
    if (status == AccountStatus.normal) return const Color(0xFF2E9E5B); // 绿
    if (status == AccountStatus.low) return const Color(0xFFE08A00); // 橙
    if (status == AccountStatus.keyValid) return const Color(0xFF2E9E5B); // 绿
    return const Color(0xFFD5484C); // 红
  }
}

/// 账号的余额状态
enum AccountStatus { normal, low, exhausted, expired, keyValid, keyInvalid, error }

/// 一条历史查询记录，画趋势图用
class HistoryPoint {
  DateTime time;
  double? remaining;
  double? used;
  double? total;

  HistoryPoint({
    required this.time,
    this.remaining,
    this.used,
    this.total,
  });

  Map<String, dynamic> toJson() {
    return {
      'time': time.toIso8601String(),
      'remaining': remaining,
      'used': used,
      'total': total,
    };
  }

  factory HistoryPoint.fromJson(Map<String, dynamic> json) {
    return HistoryPoint(
      time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
      remaining: (json['remaining'] as num?)?.toDouble(),
      used: (json['used'] as num?)?.toDouble(),
      total: (json['total'] as num?)?.toDouble(),
    );
  }
}

/// 提供商预设：常见服务商的余额接口地址和 JSON 路径都帮你填好了。
/// 选“自定义”时，这些信息需要自己填。
/// JSON 路径支持多个候选项，用英文逗号分隔，按顺序尝试（例如 “data.x,x”）。
class ProviderPreset {
  final String id;
  final String label; // 界面上显示的名字（完整）
  final String shortLabel; // 短名：添加账号时预填的默认名称
  final Color brandColor; // 提供商品牌色（徽标背景）
  final String mark; // 徽标上的缩写字符（1~2 个字符）
  final String balanceUrl; // 余额接口地址
  final String unit; // 默认单位符号；留空表示按接口返回的货币自动显示
  final String pathRemaining; // 剩余量的 JSON 路径（逗号分隔候选）
  final String pathUsed; // 已使用的 JSON 路径
  final String pathTotal; // 总额度的 JSON 路径
  final String pathCurrency; // 货币代码的 JSON 路径
  final String pathDetails; // 明细字段，多行 “显示名=JSON路径”
  final String usageAmountUrl; // 用量接口地址模板（{month}/{year} 占位），无则为空
  final String usageCostUrl; // 消费接口地址模板（可选）
  final String keyCheckUrl; // Key 校验接口（GET，返回可用模型列表），无则为空
  final String authStyle; // 认证方式：bearer / anthropic / gemini
  final String hint; // 给用户看的说明文字

  const ProviderPreset({
    required this.id,
    required this.label,
    this.shortLabel = '',
    this.brandColor = const Color(0xFF64748B),
    this.mark = '',
    required this.balanceUrl,
    this.unit = '',
    required this.hint,
    this.keyCheckUrl = '',
    this.authStyle = 'bearer',
    this.pathRemaining = '',
    this.pathUsed = '',
    this.pathTotal = '',
    this.pathCurrency = '',
    this.pathDetails = '',
    this.usageAmountUrl = '',
    this.usageCostUrl = '',
  });
}

const List<ProviderPreset> providerPresets = [
  ProviderPreset(
    id: 'deepseek',
    label: 'DeepSeek（深度求索）',
    brandColor: Color(0xFF4D6BFE),
    mark: 'DS',
    shortLabel: 'DeepSeek',
    balanceUrl: 'https://api.deepseek.com/user/balance',
    hint: '官方文档接口。返回总额/赠送/充值余额，没有“已用”，因此不显示进度条。'
        '支持用量查询：在详情页填入网页 Token 即可。',
    pathRemaining: 'balance_infos.0.total_balance',
    pathCurrency: 'balance_infos.0.currency',
    pathDetails: '赠送额度=balance_infos.0.granted_balance\n'
        '充值余额=balance_infos.0.topped_up_balance',
    usageAmountUrl:
        'https://platform.deepseek.com/api/v0/usage/amount?month={month}&year={year}',
    usageCostUrl:
        'https://platform.deepseek.com/api/v0/usage/cost?month={month}&year={year}',
  ),
  ProviderPreset(
    id: 'zhipu',
    label: '智谱 GLM（BigModel）',
    brandColor: Color(0xFF2454FF),
    mark: '智',
    shortLabel: '智谱 GLM',
    balanceUrl: 'https://open.bigmodel.cn/api/paas/v4/users/me/balance',
    hint: '社区确认的余额接口，返回可用/已用/总余额，支持进度条。海外站请选 Z.ai。',
    pathRemaining: 'data.available_balance,available_balance',
    pathUsed: 'data.used_balance,used_balance',
    pathTotal: 'data.total_balance,total_balance',
    pathCurrency: 'data.currency,currency',
  ),
  ProviderPreset(
    id: 'zai',
    label: 'Z.ai（智谱海外）',
    brandColor: Color(0xFF17181C),
    mark: 'Z',
    shortLabel: 'Z.ai',
    balanceUrl: 'https://api.z.ai/api/paas/v4/users/me/balance',
    hint: 'Z.ai 海外站的余额接口，字段与智谱国内站相同。',
    pathRemaining: 'data.available_balance,available_balance',
    pathUsed: 'data.used_balance,used_balance',
    pathTotal: 'data.total_balance,total_balance',
    pathCurrency: 'data.currency,currency',
  ),
  ProviderPreset(
    id: 'moonshot',
    label: 'Moonshot AI（Kimi）',
    brandColor: Color(0xFF39414D),
    mark: 'K',
    shortLabel: 'Kimi',
    balanceUrl: 'https://api.moonshot.cn/v1/users/me/balance',
    hint: '官方文档接口，返回可用余额以及现金/代金券明细。',
    pathRemaining: 'data.available_balance',
    pathCurrency: 'data.currency',
    pathDetails: '现金余额=data.cash_balance\n代金券=data.voucher_balance',
  ),
  ProviderPreset(
    id: 'openrouter',
    label: 'OpenRouter',
    brandColor: Color(0xFF6467F2),
    mark: 'OR',
    shortLabel: 'OpenRouter',
    balanceUrl: 'https://openrouter.ai/api/v1/credits',
    unit: r'$',
    hint: '官方文档接口，返回总额度和已用金额，剩余量自动计算。',
    pathTotal: 'data.total_credits',
    pathUsed: 'data.total_usage',
  ),
  ProviderPreset(
    id: 'siliconflow',
    label: 'SiliconFlow（硅基流动）',
    brandColor: Color(0xFF7C3AED),
    mark: 'SF',
    shortLabel: '硅基流动',
    balanceUrl: 'https://api.siliconflow.cn/v1/user/info',
    unit: '¥',
    hint: '官方文档接口，返回总余额以及充值/赠送明细。',
    pathRemaining: 'data.totalBalance',
    pathDetails: '充值余额=data.chargeBalance\n赠送余额=data.balance',
  ),
  ProviderPreset(
    id: 'custom',
    label: '自定义',
    brandColor: Color(0xFF6B7280),
    mark: '自',
    balanceUrl: '',
    hint: '填写完整的余额接口地址，以及从返回 JSON 取值的路径，例如 data.balance。'
        '路径可以填多个候选，用英文逗号分隔。',
  ),
];

/// 历史兼容：这几家没有余额接口，已不在“添加账号”列表里，
/// 但老数据里仍可能存在，保留解析。
const List<ProviderPreset> legacyPresets = [
  ProviderPreset(
    id: 'openai',
    label: 'OpenAI',
    brandColor: Color(0xFF10A37F),
    mark: 'OA',
    shortLabel: 'OpenAI',
    balanceUrl: '',
    keyCheckUrl: 'https://api.openai.com/v1/models',
    authStyle: 'bearer',
    hint: '官方不提供余额查询接口：支持 Key 校验（可用模型数），余额可在详情页手动记录。',
  ),
  ProviderPreset(
    id: 'anthropic',
    label: 'Anthropic（Claude）',
    brandColor: Color(0xFFCC785C),
    mark: 'CL',
    shortLabel: 'Claude',
    balanceUrl: '',
    keyCheckUrl: 'https://api.anthropic.com/v1/models',
    authStyle: 'anthropic',
    hint: '官方不提供余额查询接口：支持 Key 校验（可用模型数），余额可在详情页手动记录。',
  ),
  ProviderPreset(
    id: 'gemini',
    label: 'Google Gemini',
    brandColor: Color(0xFF4285F4),
    mark: 'GE',
    shortLabel: 'Gemini',
    balanceUrl: '',
    keyCheckUrl: 'https://generativelanguage.googleapis.com/v1beta/models',
    authStyle: 'gemini',
    hint: '官方不提供余额查询接口：支持 Key 校验（可用模型数），余额可在详情页手动记录。',
  ),
  ProviderPreset(
    id: 'groq',
    label: 'Groq',
    brandColor: Color(0xFFF55036),
    mark: 'GQ',
    shortLabel: 'Groq',
    balanceUrl: '',
    keyCheckUrl: 'https://api.groq.com/openai/v1/models',
    authStyle: 'bearer',
    hint: '官方不提供余额查询接口：支持 Key 校验（可用模型数），余额可在详情页手动记录。',
  ),
  ProviderPreset(
    id: 'xai',
    label: 'xAI（Grok）',
    brandColor: Color(0xFF1A1A1A),
    mark: 'X',
    shortLabel: 'xAI',
    balanceUrl: '',
    keyCheckUrl: 'https://api.x.ai/v1/models',
    authStyle: 'bearer',
    hint: '官方不提供余额查询接口：支持 Key 校验（可用模型数），余额可在详情页手动记录。',
  ),
];

/// 按 id 找提供商预设（含历史兼容列表），找不到就当作“自定义”
ProviderPreset presetById(String id) {
  for (final preset in providerPresets) {
    if (preset.id == id) return preset;
  }
  for (final preset in legacyPresets) {
    if (preset.id == id) return preset;
  }
  return providerPresets.last;
}

/// 常见货币代码 → 显示符号
const Map<String, String> currencySymbols = {
  'CNY': '¥',
  'RMB': '¥',
  'USD': r'$',
  'EUR': '€',
  'GBP': '£',
  'JPY': 'JP¥',
  'KRW': '₩',
  'HKD': 'HK\$',
  'TWD': 'NT\$',
  'SGD': 'S\$',
};

String currencySymbolOf(String? code) {
  if (code == null) return '';
  return currencySymbols[code.trim().toUpperCase()] ?? '';
}

/// 软件的设置项
class AppSettings {
  bool autoRefreshOnStart; // 打开软件时自动刷新所有模型
  int autoRefreshMinutes; // 定时自动刷新的间隔（分钟），0 表示不自动刷新
  int timeoutSeconds; // 请求超时时间（秒）
  String proxyModeName; // 网络代理：none（直连）/ system（跟随环境变量）/ manual（手动）
  String proxyAddress; // 手动代理地址，例如 127.0.0.1:7890
  bool developerMode; // 开发者模式：详情页显示接口原始返回
  String seedColorName; // 主题色的名字，对应 seedColors 里的键
  String themeModeName; // 深色模式：system / light / dark

  AppSettings({
    required this.autoRefreshOnStart,
    required this.autoRefreshMinutes,
    required this.timeoutSeconds,
    required this.proxyModeName,
    required this.proxyAddress,
    required this.developerMode,
    required this.seedColorName,
    required this.themeModeName,
  });

  factory AppSettings.defaults() {
    return AppSettings(
      autoRefreshOnStart: true,
      autoRefreshMinutes: 0, // 默认不定时刷新
      timeoutSeconds: 15,
      proxyModeName: 'none',
      proxyAddress: '',
      developerMode: false,
      seedColorName: 'slate', // 默认 Shizuku 风格石板蓝
      themeModeName: 'system',
    );
  }

  ThemeMode get themeMode {
    if (themeModeName == 'light') return ThemeMode.light;
    if (themeModeName == 'dark') return ThemeMode.dark;
    return ThemeMode.system;
  }

  /// 复制一份并替换部分字段，设置页改某一项时用
  AppSettings copyWith({
    bool? autoRefreshOnStart,
    int? autoRefreshMinutes,
    int? timeoutSeconds,
    String? proxyModeName,
    String? proxyAddress,
    bool? developerMode,
    String? seedColorName,
    String? themeModeName,
  }) {
    return AppSettings(
      autoRefreshOnStart: autoRefreshOnStart ?? this.autoRefreshOnStart,
      autoRefreshMinutes: autoRefreshMinutes ?? this.autoRefreshMinutes,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      proxyModeName: proxyModeName ?? this.proxyModeName,
      proxyAddress: proxyAddress ?? this.proxyAddress,
      developerMode: developerMode ?? this.developerMode,
      seedColorName: seedColorName ?? this.seedColorName,
      themeModeName: themeModeName ?? this.themeModeName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'autoRefreshOnStart': autoRefreshOnStart,
      'autoRefreshMinutes': autoRefreshMinutes,
      'timeoutSeconds': timeoutSeconds,
      'proxyModeName': proxyModeName,
      'proxyAddress': proxyAddress,
      'developerMode': developerMode,
      'seedColorName': seedColorName,
      'themeModeName': themeModeName,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final defaults = AppSettings.defaults();
    return AppSettings(
      autoRefreshOnStart: json['autoRefreshOnStart'] as bool? ?? defaults.autoRefreshOnStart,
      autoRefreshMinutes: json['autoRefreshMinutes'] as int? ?? defaults.autoRefreshMinutes,
      timeoutSeconds: json['timeoutSeconds'] as int? ?? defaults.timeoutSeconds,
      proxyModeName: json['proxyModeName'] as String? ?? defaults.proxyModeName,
      proxyAddress: json['proxyAddress'] as String? ?? defaults.proxyAddress,
      developerMode: json['developerMode'] as bool? ?? defaults.developerMode,
      seedColorName: const {'indigo': 'slate', 'purple': 'slate', 'pink': 'slate'}[
              json['seedColorName'] as String?] ??
          json['seedColorName'] as String? ??
          defaults.seedColorName,
      themeModeName: json['themeModeName'] as String? ?? defaults.themeModeName,
    );
  }
}

/// 应用的全部本地数据：模型列表 + 设置
class AppData {
  List<ModelAccount> models;
  AppSettings settings;

  AppData({required this.models, required this.settings});

  factory AppData.empty() {
    return AppData(models: [], settings: AppSettings.defaults());
  }

  Map<String, dynamic> toJson() {
    return {
      'models': models.map((m) => m.toJson()).toList(),
      'settings': settings.toJson(),
    };
  }
}

/// 可选的主题色，第一项 Indigo 是默认色
const Map<String, Color> seedColors = {
  'slate': Color(0xFF48607C), // Shizuku 风格的石板蓝（默认）
  'indigo': Color(0xFF3F51B5),
  'blue': Color(0xFF1565C0),
  'teal': Color(0xFF00695C),
};

/// 把 JSON 编码成好看的缩进格式（导出/调试时容易看）
String toPrettyJson(Object data) {
  return const JsonEncoder.withIndent('  ').convert(data);
}
