import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'models.dart';
import 'utils.dart';

/// 用量查询服务（一期：手动粘贴网页 Token）。
///
/// DeepSeek 官方 API 只有余额接口，没有用量统计接口。用量数据来自平台网页版
/// 的内部接口（参考社区逆向分析），鉴权用的是“网页登录 Token”而不是 API Key：
///   1. 浏览器登录 platform.deepseek.com
///   2. F12 控制台执行 JSON.parse(localStorage.userToken).value
///   3. 把得到的字符串粘贴进应用（详情页 → 本月用量 → 填入 Token）
///
/// 网页 Token 短期有效，失效后重复上面的步骤即可。
/// 这里的取 Token 入口刻意收拢在 buildUsageHeaders() 一个函数里，
/// 将来升级“应用内 WebView 自动抓取”时只需要替换这一处。
///
/// ⚠️ 内部接口没有官方 SLA，结构可能变化，所以解析全部走防御式：
/// 取不到的字段一律置空/为零，绝不抛异常（Token 失效除外）。

/// 模拟浏览器的请求头：内部接口会校验这些，不带会被拒
const String usageBrowserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
const String usageAppVersion = '1.0.0';

/// 指标类型名（来自平台接口）
const typePromptCacheHit = 'PROMPT_CACHE_HIT_TOKEN'; // 输入命中缓存
const typePromptCacheMiss = 'PROMPT_CACHE_MISS_TOKEN'; // 输入未命中缓存
const typeResponseToken = 'RESPONSE_TOKEN'; // 输出 Token
const typeRequest = 'REQUEST'; // 请求次数
const typePromptToken = 'PROMPT_TOKEN'; // 输入 Token（总量）

/// 一个模型的当月用量汇总
class ModelUsage {
  final String model;
  final Map<String, double> byType; // 指标名 → 数量

  ModelUsage(this.model, this.byType);

  /// 月度总 Token：各指标求和（按文章口径，REQUEST 请求次数除外）
  double get totalTokens {
    var sum = 0.0;
    byType.forEach((type, amount) {
      if (type != typeRequest) sum += amount;
    });
    return sum;
  }

  double get cacheHit => byType[typePromptCacheHit] ?? 0;
  double get cacheMiss => byType[typePromptCacheMiss] ?? 0;
  double get requests => byType[typeRequest] ?? 0;

  /// 缓存命中率：命中 / (命中 + 未命中)，没有输入就返回 null（显示 “—”）
  double? get cacheHitRate {
    final input = cacheHit + cacheMiss;
    if (input <= 0) return null;
    return cacheHit / input;
  }
}

/// 一天的用量
class DailyUsage {
  final DateTime date;
  final double tokens;

  DailyUsage(this.date, this.tokens);
}

/// 一次用量查询的完整结果
class UsageReport {
  final int year;
  final int month;
  final List<ModelUsage> models; // 按模型汇总
  final List<DailyUsage> days; // 按天明细
  final double? totalCost; // 当月消费金额（消费接口解析失败时为 null）
  final String rawJson; // 用量接口的原始返回，详情页可查看

  UsageReport({
    required this.year,
    required this.month,
    required this.models,
    required this.days,
    this.totalCost,
    required this.rawJson,
  });

  double get totalTokens =>
      models.fold(0, (sum, m) => sum + m.totalTokens);

  double? get cacheHitRate {
    var hit = 0.0;
    var miss = 0.0;
    for (final m in models) {
      hit += m.cacheHit;
      miss += m.cacheMiss;
    }
    if (hit + miss <= 0) return null;
    return hit / (hit + miss);
  }
}

/// 查询某年某月的用量（month: 1 ~ 12）
Future<UsageReport> fetchUsage(
  ModelAccount account,
  AppSettings settings, {
  required int year,
  required int month,
}) async {
  final token = account.usageToken.trim();
  if (token.isEmpty) {
    throw Exception('还没有填入网页 Token，点“填入 Token”按提示操作');
  }

  final amountUrl = account.effectiveUsageAmountUrl
      .replaceAll('{month}', '$month')
      .replaceAll('{year}', '$year');
  if (amountUrl.isEmpty) {
    throw Exception('该提供商没有配置用量接口地址');
  }

  final rawJson = await _getJson(
    amountUrl,
    token,
    settings: settings,
    expiredHint: '网页 Token 已失效，请重新获取并更新',
  );

  // ── 解析按模型汇总 + 按天明细 ──
  // 结构：biz_data.total[] / biz_data.days[]，
  // 但有的接口会把 biz_data 包在 data 里，所以两种路径都试。
  dynamic decodedRoot;
  try {
    decodedRoot = jsonDecode(rawJson);
  } catch (_) {
    throw Exception('用量接口返回的内容不是合法的 JSON');
  }
  final biz = pickFirstByPaths(decodedRoot, 'data.biz_data,biz_data,data');

  final models = <ModelUsage>[];
  final days = <DailyUsage>[];
  if (biz is Map) {
    final totalList = biz['total'];
    if (totalList is List) {
      for (final item in totalList) {
        if (item is! Map) continue;
        final model = item['model']?.toString() ?? '未知模型';
        models.add(ModelUsage(model, _parseUsageList(item['usage'])));
      }
    }
    final daysList = biz['days'] ?? biz['day_list'] ?? biz['daily'];
    if (daysList is List) {
      for (final dayItem in daysList) {
        if (dayItem is! Map) continue;
        final date = DateTime.tryParse(dayItem['date']?.toString() ?? '');
        if (date == null) continue;
        // 每天的用量：不同版本的接口里字段名不一样，data / usage 都试一下
        final usage = _parseUsageList(dayItem['data'] ?? dayItem['usage']);
        days.add(DailyUsage(date, _sumTokens(usage)));
      }
    }
  }

  // ── 解析当月消费（可选，失败不影响用量展示） ──
  double? totalCost;
  final costUrl = account.effectiveUsageCostUrl
      .replaceAll('{month}', '$month')
      .replaceAll('{year}', '$year');
  if (costUrl.isNotEmpty) {
    try {
      final costJson = await _getJson(
        costUrl,
        token,
        settings: settings,
        expiredHint: '网页 Token 已失效，请重新获取并更新',
      );
      totalCost = _parseTotalCost(costJson);
    } catch (_) {
      totalCost = null; // 消费接口挂了就先不显示消费
    }
  }

  if (models.isEmpty && days.isEmpty) {
    throw Exception('用量接口返回了无法识别的数据，可能接口已变更（可在下方查看原始返回）');
  }

  return UsageReport(
    year: year,
    month: month,
    models: models,
    days: days,
    totalCost: totalCost,
    rawJson: rawJson,
  );
}

// ─────────────────────────── 内部工具 ───────────────────────────

/// 带伪装头发起 GET，返回响应原文；Token 失效时抛出带指引的错误
Future<String> _getJson(
  String url,
  String token, {
  required AppSettings settings,
  required String expiredHint,
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null) throw Exception('用量接口地址不合法：$url');

  final client = buildHttpClient(settings);
  http.Response response;
  try {
    response = await client
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'User-Agent': usageBrowserUserAgent,
            'x-app-version': usageAppVersion,
            'Accept': 'application/json',
          },
        )
        .timeout(Duration(seconds: settings.timeoutSeconds));
  } on TimeoutException {
    throw Exception('用量查询超时，请稍后重试');
  } catch (_) {
    throw Exception('用量查询的网络请求失败，请检查网络（用代理的话也检查下代理设置）');
  } finally {
    client.close();
  }

  final body = utf8.decode(response.bodyBytes);

  // 平台的错误返回形如 {"code":40003,"msg":"Authorization Failed...","data":null}
  dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    decoded = null; // 不是 JSON 就跳过错误识别，交给外层防御式解析
  }
  if (decoded is Map) {
    final code = decoded['code'];
    final msg = decoded['msg']?.toString() ?? '';
    final isAuthError = code == 40003 ||
        code == 401 ||
        msg.toLowerCase().contains('authorization');
    if (isAuthError) throw Exception(expiredHint);
    if (code is int && code >= 400 && code != 200) {
      throw Exception('用量接口返回错误：$msg');
    }
  }

  if (response.statusCode != 200) {
    throw Exception('用量接口返回了错误（HTTP ${response.statusCode}）');
  }
  return body;
}

/// 解析 usage 数组：[{type, amount}] → {type: 数量}
Map<String, double> _parseUsageList(dynamic usageList) {
  final result = <String, double>{};
  if (usageList is List) {
    for (final item in usageList) {
      if (item is! Map) continue;
      final type = item['type']?.toString();
      final amount = toDouble(item['amount']);
      if (type == null || amount == null) continue;
      result[type] = (result[type] ?? 0) + amount;
    }
  }
  return result;
}

/// 一个 usage 映射里的 Token 总量（REQUEST 次数除外）
double _sumTokens(Map<String, double> usage) {
  var sum = 0.0;
  usage.forEach((type, amount) {
    if (type != typeRequest) sum += amount;
  });
  return sum;
}

/// 解析消费接口的返回，取当月总消费。
/// 文章说明：cost 接口的 biz_data 是数组，第一项包含总消费和每日明细，
/// 字段名未公开，这里按“和用量接口同样的 model/usage 结构”防御式解析。
double? _parseTotalCost(String body) {
  try {
    final json = jsonDecode(body);
    dynamic biz = pickFirstByPaths(json, 'data.biz_data,biz_data');
    if (biz is List && biz.isNotEmpty) biz = biz.first;
    if (biz is! Map) return null;

    // 先试直接给总额的字段名
    for (final key in ['total_cost', 'total_amount', 'amount', 'cost']) {
      final value = toDouble(biz[key]);
      if (value != null) return value;
    }
    // 再按 model/usage 结构求和
    final totalList = biz['total'];
    if (totalList is List) {
      var sum = 0.0;
      var found = false;
      for (final item in totalList) {
        if (item is! Map) continue;
        final usage = _parseUsageList(item['usage']);
        usage.forEach((_, amount) {
          sum += amount;
          found = true;
        });
      }
      if (found) return sum;
    }
    return null;
  } catch (_) {
    return null;
  }
}
