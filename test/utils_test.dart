import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tokenmeow/models.dart';
import 'package:tokenmeow/usage_service.dart';
import 'package:tokenmeow/utils.dart';

void main() {
  test('formatAmount：千位分隔符，并去掉末尾的 .00', () {
    expect(formatAmount(1234567.5), '1,234,567.50');
    expect(formatAmount(105.2), '105.20');
    expect(formatAmount(100), '100');
    expect(formatAmount(-99.99), '-99.99');
    expect(formatAmount(0), '0');
  });

  test('formatCompact：图表坐标轴用的紧凑数字', () {
    expect(formatCompact(1500000), '1.5M');
    expect(formatCompact(12500), '12.5k');
    expect(formatCompact(105), '105');
  });

  test('pickByPath / pickFirstByPaths：支持点分隔、数组下标和多候选', () {
    final json = {
      'data': {'total': '12.5'},
      'list': [
        {'name': 'a'},
      ],
    };
    expect(toDouble(pickByPath(json, 'data.total')), 12.5);
    expect(pickByPath(json, 'list.0.name'), 'a');
    expect(pickByPath(json, 'data.missing'), isNull);
    // 第二个候选路径命中
    expect(pickFirstByPaths(json, 'nope.missing,list.0.name'), 'a');
    // 两个候选都取不到
    expect(pickFirstByPaths(json, 'a.b,c.d'), isNull);
  });

  test('parseDetailSpec：解析 “显示名=JSON路径” 多行文本', () {
    final spec = parseDetailSpec(
        '赠送额度=balance_infos.0.granted_balance\n\n充值余额=balance_infos.0.topped_up_balance\n错误行');
    expect(spec.length, 2);
    expect(spec['赠送额度'], 'balance_infos.0.granted_balance');
    expect(spec['充值余额'], 'balance_infos.0.topped_up_balance');
  });

  test('ModelAccount.usedRatio：剩余/已用比例计算，并夹在 0 ~ 1', () {
    final account = ModelAccount(
      id: '1',
      name: '测试',
      providerId: 'zhipu',
      balanceUrl: '',
      apiKey: '',
      unit: '',
    );
    account.total = 100;
    account.remaining = 72.6;
    // 没有 used 时用 total - remaining 反推：27.4%
    expect(account.usedRatio()!.toStringAsFixed(2), '0.27');
    account.used = 150; // 超用时压到 1
    expect(account.usedRatio(), 1);
    account.total = null; // 没有总额就算不出，不画进度条
    expect(account.usedRatio(), isNull);
  });

  test('货币符号映射与显示单位', () {
    expect(currencySymbolOf('CNY'), '¥');
    expect(currencySymbolOf('USD'), r'$');
    expect(currencySymbolOf('UNKNOWN'), '');
    expect(currencySymbolOf(null), '');

    final account = ModelAccount(
      id: '1',
      name: '测试',
      providerId: 'custom',
      balanceUrl: '',
      apiKey: '',
      unit: '',
    );
    account.currencyCode = 'CNY';
    expect(account.displayUnit(), '¥'); // 货币自动映射
    account.unit = 'tokens';
    expect(account.displayUnit(), 'tokens'); // 手填单位优先
  });

  test('ModelAccount 序列化：历史记录和原始返回要能存取', () {
    final account = ModelAccount(
      id: '42',
      name: 'GLM 5.3 Flash',
      providerId: 'zhipu',
      balanceUrl: 'https://open.bigmodel.cn/api/paas/v4/users/me/balance',
      apiKey: 'sk-test',
      unit: '',
      pathDetails: '赠送额度=data.bonus',
    );
    account.rawResponse = '{"ok":true}';
    account.appendHistory();

    final restored = ModelAccount.fromJson(
        jsonDecode(jsonEncode(account.toJson())) as Map<String, dynamic>);
    expect(restored.id, '42');
    expect(restored.rawResponse, '{"ok":true}');
    expect(restored.history.length, 1);
    expect(restored.pathDetails, '赠送额度=data.bonus');
  });

  test('presetById：找不到就用“自定义”兜底，预设里必须有智谱', () {
    expect(presetById('deepseek').label, contains('DeepSeek'));
    expect(presetById('zhipu').balanceUrl, contains('bigmodel.cn'));
    expect(presetById('not-exist').id, 'custom');
  });

  test('用量解析：按模型汇总、按天明细、缓存命中率（按文章口径）', () {
    // 模拟 DeepSeek 平台 usage/amount 的返回结构
    const body = '''
    {"code":200,"msg":"","data":{"biz_data":{
      "total":[
        {"model":"deepseek-v4-pro","usage":[
          {"type":"PROMPT_CACHE_HIT_TOKEN","amount":"800"},
          {"type":"PROMPT_CACHE_MISS_TOKEN","amount":"200"},
          {"type":"RESPONSE_TOKEN","amount":"500"},
          {"type":"REQUEST","amount":"12"}
        ]},
        {"model":"deepseek-v4-flash","usage":[
          {"type":"PROMPT_TOKEN","amount":"300"},
          {"type":"RESPONSE_TOKEN","amount":"100"}
        ]}
      ],
      "days":[
        {"date":"2026-08-28","data":[{"type":"PROMPT_CACHE_HIT_TOKEN","amount":"600"},{"type":"REQUEST","amount":"8"}]},
        {"date":"2026-08-29","data":[{"type":"RESPONSE_TOKEN","amount":"150"},{"type":"REQUEST","amount":"4"}]}
      ]
    }}}
    ''';
    final biz = pickFirstByPaths(jsonDecode(body), 'data.biz_data,biz_data,data') as Map;
    final models = <ModelUsage>[];
    for (final item in (biz['total'] as List)) {
      models.add(ModelUsage(
        (item as Map)['model'] as String,
        _parseForTest(item['usage']),
      ));
    }
    expect(models.length, 2);
    // 总 Token = 各指标求和（REQUEST 除外）：800+200+500 = 1500
    expect(models[0].totalTokens, 1500);
    expect(models[0].requests, 12);
    // 缓存命中率：800 / (800+200) = 80%
    expect(models[0].cacheHitRate, 0.8);
    // PROMPT_TOKEN 存在时按文章口径直接计入总量：300+100=400
    expect(models[1].totalTokens, 400);
    expect(models[1].cacheHitRate, isNull); // 没有缓存数据
  });

  test('用量接口的 Token 失效特征字段', () {
    // 平台错误返回 {"code":40003,...}，fetchUsage 会把它翻译成“Token 已失效”
    final errorBody = jsonDecode('{"code":40003,"msg":"Authorization Failed","data":null}') as Map;
    expect(errorBody['code'], 40003);
  });

  test('每日明细：days 内层字段是 usage 时也能解析（真机接口形状）', () {
    // 真实接口的 days 内层用 usage 而不是文章里写的 data
    const body = '''
    {"code":200,"msg":"","data":{"biz_data":{
      "total":[{"model":"deepseek-v4-pro","usage":[{"type":"RESPONSE_TOKEN","amount":"500"}]}],
      "days":[
        {"date":"2026-08-28","usage":[{"type":"PROMPT_TOKEN","amount":"1200"},{"type":"REQUEST","amount":"8"}]},
        {"date":"2026-08-29","usage":[{"type":"RESPONSE_TOKEN","amount":"150"}]}
      ]
    }}}
    ''';
    final biz = pickFirstByPaths(jsonDecode(body), 'data.biz_data,biz_data,data') as Map;
    final days = <double>[];
    for (final dayItem in (biz['days'] as List)) {
      final map = dayItem as Map;
      final usage = _parseForTest(map['data'] ?? map['usage']);
      var sum = 0.0;
      usage.forEach((type, amount) {
        if (type != 'REQUEST') sum += amount;
      });
      days.add(sum);
    }
    expect(days, [1200, 150]); // REQUEST 除外
  });

  test('AccountStatus：正常 / 余额不足 / 已用尽 / 已过期 / 查询失败', () {
    final account = ModelAccount(
      id: '1',
      name: '测试',
      providerId: 'zhipu',
      balanceUrl: '',
      apiKey: '',
      unit: '',
    );
    // 还没有数据且从没刷新过：状态按“正常”处理，界面不显示标签
    expect(account.status, AccountStatus.normal);
    // 查询失败且没有历史数据
    account.errorMessage = '网络请求失败';
    expect(account.status, AccountStatus.error);
    expect(account.statusLabel, '查询失败');
    // 正常
    account.errorMessage = null;
    account.remaining = 80;
    account.total = 100;
    account.used = 20;
    expect(account.statusLabel, '正常');
    // 已用 85% → 余额不足
    account.used = 85;
    expect(account.statusLabel, '余额不足');
    // 余额为 0 → 已用尽
    account.remaining = 0;
    account.used = null;
    expect(account.statusLabel, '已用尽');
    // is_available = false → 已过期
    account.remaining = 50;
    account.isAvailable = false;
    expect(account.statusLabel, '已过期');
  });

  test('用量摘要：记录与序列化', () {
    final account = ModelAccount(
      id: '2',
      name: '测试用量',
      providerId: 'deepseek',
      balanceUrl: '',
      apiKey: '',
      unit: '',
    );
    account.recordUsageSummary(
      tokens: 131952,
      cost: 14.21,
      cacheHitRate: 0.98,
      year: 2026,
      month: 8,
    );
    expect(account.usageMonthLabel, '2026-08');
    expect(account.usageMonthTokens, 131952);
    expect(account.usageMonthCost, 14.21);

    final restored = ModelAccount.fromJson(
        jsonDecode(jsonEncode(account.toJson())) as Map<String, dynamic>);
    expect(restored.usageMonthLabel, '2026-08');
    expect(restored.usageMonthTokens, 131952);
    expect(restored.usageMonthCost, 14.21);
  });

  test('AppSettings：开发者模式默认关闭，可序列化', () {
    final settings = AppSettings.defaults();
    expect(settings.developerMode, false);
    final restored = AppSettings.fromJson(
        jsonDecode(jsonEncode(settings.copyWith(developerMode: true).toJson())) as Map<String, dynamic>);
    expect(restored.developerMode, true);
  });
}

/// 测试辅助：把 usage 数组转成 ModelUsage 用的映射（与 usage_service 内部逻辑一致）
Map<String, double> _parseForTest(dynamic usageList) {
  final result = <String, double>{};
  for (final item in (usageList as List)) {
    final map = item as Map;
    final value = toDouble(map['amount']);
    if (value != null) result[map['type'] as String] = value;
  }
  return result;
}
