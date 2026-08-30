import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'models.dart';
import 'utils.dart';

/// 一次余额查询的结果
class BalanceResult {
  final double? remaining; // 剩余量
  final double? used; // 已使用
  final double? total; // 总额度
  final Map<String, double> details; // 其他明细字段（赠送额度、充值余额等）
  final String? currencyCode; // 货币代码，如 CNY、USD
  final bool? isAvailable; // 可用标志（没返回就是 null）
  final String rawJson; // 接口的原始返回文本，详情页可以查看

  const BalanceResult({
    this.remaining,
    this.used,
    this.total,
    this.details = const {},
    this.currencyCode,
    this.isAvailable,
    required this.rawJson,
  });
}

/// 根据设置创建带代理功能的 HTTP 客户端。
/// Dart 的 HttpClient 默认“直连”，不走系统代理，所以手动代理要在这里配置。
http.Client buildHttpClient(AppSettings settings) {
  final httpClient = HttpClient();

  if (settings.proxyModeName == 'system') {
    // 跟随 HTTP_PROXY / HTTPS_PROXY 环境变量
    httpClient.findProxy = HttpClient.findProxyFromEnvironment;
  } else if (settings.proxyModeName == 'manual') {
    // 手动代理：地址形如 127.0.0.1:7890 或 http://127.0.0.1:7890
    final address =
        settings.proxyAddress.trim().replaceFirst(RegExp(r'^https?://'), '');
    if (address.isNotEmpty) {
      httpClient.findProxy = (uri) => 'PROXY $address';
    }
  }

  return IOClient(httpClient);
}

/// 调用余额接口并把结果解析出来。
/// 请求统一用 GET 加 “Authorization: Bearer 【API Key】” 的请求头，这是各家接口的通用做法。
/// 出错时抛出带中文说明的 Exception，界面上直接把这句话显示出来就行。
Future<BalanceResult> fetchBalance(
  ModelAccount account, {
  required AppSettings settings,
}) async {
  final url = account.balanceUrl.trim();
  if (url.isEmpty) {
    throw Exception('接口地址是空的，请编辑这条模型补充地址');
  }
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw Exception('接口地址不合法：$url');
  }

  final client = buildHttpClient(settings);
  http.Response response;
  try {
    response = await client
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer ${account.apiKey.trim()}',
            'Accept': 'application/json',
          },
        )
        .timeout(Duration(seconds: settings.timeoutSeconds));
  } on TimeoutException {
    throw Exception('请求超时（超过 ${settings.timeoutSeconds} 秒），请检查网络后重试');
  } catch (_) {
    throw Exception('网络请求失败，请检查接口地址和本机网络（用代理的话也检查下代理设置）');
  } finally {
    client.close();
  }

  // 把常见的 HTTP 错误翻译成人话
  if (response.statusCode == 401 || response.statusCode == 403) {
    throw Exception('API Key 无效或没有权限（HTTP ${response.statusCode}）');
  }
  if (response.statusCode == 404) {
    throw Exception('接口地址不存在（HTTP 404），请检查 URL 是否填对');
  }
  if (response.statusCode != 200) {
    throw Exception('接口返回了错误（HTTP ${response.statusCode}）');
  }

  final rawJson = utf8.decode(response.bodyBytes);
  dynamic json;
  try {
    json = jsonDecode(rawJson);
  } catch (_) {
    throw Exception('接口返回的内容不是合法的 JSON');
  }

  // 优先用模型自己保存的路径，没有就用提供商预设的路径。
  // 路径支持多个候选（英文逗号分隔），按顺序尝试。
  final preset = presetById(account.providerId);
  final remaining = toDouble(
      pickFirstByPaths(json, joinPaths(account.pathRemaining, preset.pathRemaining)));
  final used = toDouble(
      pickFirstByPaths(json, joinPaths(account.pathUsed, preset.pathUsed)));
  final total = toDouble(
      pickFirstByPaths(json, joinPaths(account.pathTotal, preset.pathTotal)));
  final currency = pickFirstByPaths(
      json, joinPaths(account.pathCurrency, preset.pathCurrency));

  if (remaining == null && used == null && total == null) {
    throw Exception('在返回的 JSON 里找不到额度数据，请检查 JSON 路径是否填对');
  }

  // 有的接口只给“总额”和“已用”，那就自己算出剩余量
  double? actualRemaining = remaining;
  if (actualRemaining == null && total != null && used != null) {
    actualRemaining = total - used;
  }

  // 解析明细字段（赠送额度、充值余额、代金券等）
  final details = <String, double>{};
  final detailSpec = account.pathDetails.trim().isNotEmpty
      ? account.pathDetails
      : preset.pathDetails;
  parseDetailSpec(detailSpec).forEach((label, candidates) {
    final value = toDouble(pickFirstByPaths(json, candidates));
    if (value != null) details[label] = value;
  });

  // 可用标志（DeepSeek 返回 is_available，false 表示账号已过期/停用）
  final availableFlag =
      pickFirstByPaths(json, 'is_available,data.is_available');

  return BalanceResult(
    remaining: actualRemaining,
    used: used,
    total: total,
    details: details,
    currencyCode: currency is String ? currency : null,
    isAvailable: availableFlag is bool ? availableFlag : null,
    rawJson: rawJson,
  );
}

/// 模型自己保存的路径优先，为空则用预设的路径
String joinPaths(String? own, String preset) {
  final ownTrimmed = own?.trim() ?? '';
  if (ownTrimmed.isNotEmpty) return ownTrimmed;
  return preset.trim();
}

/// 一次 Key 校验的结果
class KeyCheckResult {
  final bool valid; // Key 是否有效
  final int modelCount; // 返回的可用模型数量

  const KeyCheckResult({required this.valid, required this.modelCount});
}

/// 按提供商的认证方式组装请求头。
/// 大多数走 Bearer；Anthropic 用 x-api-key + 版本号；Gemini 用 x-goog-api-key。
Map<String, String> authHeadersFor(String authStyle, String apiKey) {
  if (authStyle == 'anthropic') {
    return {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    };
  }
  if (authStyle == 'gemini') {
    return {'x-goog-api-key': apiKey};
  }
  return {'Authorization': 'Bearer $apiKey'};
}

/// 校验 Key：调提供商的“模型列表”接口（这是各家都有的标准接口）。
/// Key 无效（401/403）不算异常，返回 valid = false 让界面显示“Key 失效”。
Future<KeyCheckResult> validateApiKey(
  ModelAccount account, {
  required AppSettings settings,
}) async {
  final url = account.effectiveKeyCheckUrl;
  if (url.isEmpty) throw Exception('该提供商没有配置 Key 校验接口');

  final client = buildHttpClient(settings);
  http.Response response;
  try {
    response = await client
        .get(
          Uri.parse(url),
          headers: {
            ...authHeadersFor(
                presetById(account.providerId).authStyle, account.apiKey.trim()),
            'Accept': 'application/json',
          },
        )
        .timeout(Duration(seconds: settings.timeoutSeconds));
  } on TimeoutException {
    throw Exception('Key 校验超时，请稍后重试');
  } catch (_) {
    throw Exception('Key 校验的网络请求失败，请检查网络（用代理的话也检查下代理设置）');
  } finally {
    client.close();
  }

  if (response.statusCode == 401 || response.statusCode == 403) {
    return const KeyCheckResult(valid: false, modelCount: 0);
  }
  if (response.statusCode != 200) {
    throw Exception('Key 校验接口返回了错误（HTTP ${response.statusCode}）');
  }

  // 数一数模型列表里有几个模型（OpenAI/Groq/xAI 是 data，Gemini 是 models）
  var count = 0;
  try {
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is Map) {
      final list = json['data'] ?? json['models'];
      if (list is List) count = list.length;
    }
  } catch (_) {
    // 解析不了就当 0 个，Key 有效性以 HTTP 状态为准
  }
  return KeyCheckResult(valid: true, modelCount: count);
}
