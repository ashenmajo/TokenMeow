import 'package:flutter/material.dart';

import 'home_page.dart';
import 'models.dart';
import 'storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TokenMeowApp());
}

/// 应用入口：负责加载/保存本地数据，以及根据设置生成主题
class TokenMeowApp extends StatefulWidget {
  const TokenMeowApp({super.key});

  @override
  State<TokenMeowApp> createState() => _TokenMeowAppState();
}

class _TokenMeowAppState extends State<TokenMeowApp> {
  // 启动时先读文件，读完才有值；为 null 表示还在读取
  AppData? appData;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await loadAppData();
    if (!mounted) return;
    setState(() => appData = data);
  }

  /// 保存当前数据到文件
  Future<void> _save() async {
    final data = appData;
    if (data != null) await saveAppData(data);
  }

  /// 设置页改了设置后回调到这里：立刻生效并保存
  Future<void> updateSettings(AppSettings newSettings) async {
    if (appData == null) return;
    setState(() => appData!.settings = newSettings);
    await _save();
  }

  /// 主页面的模型列表有增删改后回调到这里：保存到文件
  Future<void> updateModels(List<ModelAccount> models) async {
    if (appData == null) return;
    setState(() => appData!.models = models);
    await _save();
  }

  /// 设置页导入 / 清空数据时回调到这里：整体替换并保存
  Future<void> replaceAllData(AppData newData) async {
    setState(() => appData = newData);
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final data = appData;
    final settings = data?.settings ?? AppSettings.defaults();

    return MaterialApp(
      title: 'TokenMeow',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light, settings),
      darkTheme: _buildTheme(Brightness.dark, settings),
      themeMode: settings.themeMode,
      home: data == null
            // 数据还没读完时先显示一个加载圈
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : HomePage(
              models: data.models,
              settings: data.settings,
          onSettingsChanged: updateSettings,
          onModelsChanged: updateModels,
          onDataReplaced: replaceAllData,
        ),
    );
  }

  /// Material 3 主题：从主题色种子生成整套配色，跟随系统深浅色模式。
  /// 背景压深一层（surfaceContainer），卡片浮在更浅的一层上，层次更清楚；
  /// 主色保持种子的经典靛蓝，按钮、图标等强调色全部统一用它。
  ThemeData _buildTheme(Brightness brightness, AppSettings settings) {
    final seed = seedColors[settings.seedColorName] ?? seedColors['indigo']!;
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    // 参考风格（同 Shizuku）：白色页面背景 + 带浅浅主题色的圆角卡片。
    // 卡片底色从主色取色相、手动定饱和度/亮度（Material 容器色板饱和度
    // 太低，直接用几乎看不出主题色）。cardTheme 保证所有 Card 都生效。
    final baseHsl = HSLColor.fromColor(scheme.primary);
    final isDark = brightness == Brightness.dark;
    final cardColor = baseHsl
        .withSaturation(isDark ? 0.20 : 0.28)
        .withLightness(isDark ? 0.17 : 0.958)
        .toColor();
    return ThemeData(
      // 全局使用捆绑的中文字体（NotoSansSC），Windows/Android 渲染一致
      fontFamily: 'NotoSansSC',
      // 关键：把生成的配色传给 ThemeData。之前这行被改丢过，
      // 导致 ThemeData 用默认紫色配色，界面全部偏紫。
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? scheme.surface : Colors.white,
      appBarTheme: AppBarTheme(
          backgroundColor: isDark ? scheme.surface : Colors.white),
      cardColor: cardColor,
      cardTheme: CardThemeData(color: cardColor),
      // FAB 与 FilledButton（保存等）统一用实心主色，不要浅底深字
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const CircleBorder(),
      ),
      // 分段按钮（柱状图/折线图切换）选中态锁死主色，
      // 不用默认的 secondaryContainer，保证和主题一致
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? scheme.primary : null),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? scheme.onPrimary
                  : null),
        ),
      ),
      // 页面切换用 MD3 的“淡入前移”，替代默认的缩放过渡
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
