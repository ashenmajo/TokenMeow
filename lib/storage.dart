import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel;

import 'models.dart';

/// 应用的所有本地数据（模型列表 + 设置）都存在一个 JSON 文件里：
/// - Android：应用私有目录（目录路径由 MainActivity 通过 MethodChannel 告诉我们）
///
/// 特意不用 shared_preferences 这类插件，是为了让 Windows 端构建不依赖
/// 系统的“开发者模式”（Flutter 插件在 Windows 上构建需要符号链接权限）。
const MethodChannel _platformChannel = MethodChannel(
  'dev.meowworks.tokenmeow/platform',
);

/// 数据文件的完整路径
Future<String> dataFilePath() async {
  if (Platform.isAndroid) {
    final filesDir = await _platformChannel.invokeMethod<String>('getFilesDir');
    return '$filesDir/tokenmeow_data.json';
  }

  // Windows（以及其他桌面平台）：放在 %APPDATA% 下
  final appData = Platform.environment['APPDATA'] ?? Directory.current.path;
  final folder = Directory('$appData/TokenMeow');
  if (!folder.existsSync()) {
    folder.createSync(recursive: true);
  }
  return '${folder.path}/tokenmeow_data.json';
}

/// 从文件里读出全部数据；文件不存在或损坏时返回默认值，不让应用崩掉
Future<AppData> loadAppData() async {
  try {
    final file = File(await dataFilePath());
    if (!file.existsSync()) return AppData.empty();

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) return AppData.empty();

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

    return AppData(models: models, settings: settings);
  } catch (_) {
    return AppData.empty();
  }
}

/// 把全部数据整体写回文件。数据量很小，每次改动后全量保存一次，逻辑最简单。
Future<void> saveAppData(AppData data) async {
  final file = File(await dataFilePath());
  await file.writeAsString(toPrettyJson(data.toJson()));
}
