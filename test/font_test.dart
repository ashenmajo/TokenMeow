import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证捆绑的中文字体（assets/fonts/）可用：
/// 1. 资源能通过 rootBundle 加载（pubspec 注册正确）；
/// 2. 可变字体的 wght 轴随 fontWeight 自动生效（Flutter 3.41+）——
///    w700 渲染宽度应比 w400 更宽，而非假粗体合成。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('NotoSansSC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'));
    await loader.load();
  });

  testWidgets('NotoSansSC 中文渲染且字重生效', (tester) async {
    double width(FontWeight w) {
      final tp = TextPainter(
        text: TextSpan(
          text: '中文渲染测试TokenMeow',
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 24,
            fontWeight: w,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp.width;
    }

    final regular = width(FontWeight.w400);
    final bold = width(FontWeight.w700);
    expect(regular, greaterThan(0), reason: '字体应能正常布局出中文');
    expect(bold, greaterThan(regular),
        reason: 'w700 应命中 Bold 字重文件（比 Regular 宽）');
  });
}
