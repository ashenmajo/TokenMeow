import 'package:flutter/material.dart';

import '../models.dart';

/// 提供商徽标：优先显示本地保存的品牌 logo，加载失败回退为
/// 品牌色 + 缩写字符的圆角方块。
class ProviderBadge extends StatelessWidget {
  final ProviderPreset preset;
  final double size;

  const ProviderBadge({super.key, required this.preset, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          'assets/providers/${preset.id}.png',
          fit: BoxFit.cover,
          // 没有 logo 资源时用品牌色 + 缩写兜底
          errorBuilder: (_, _, _) => Container(
            color: preset.brandColor,
            alignment: Alignment.center,
            child: Text(
              preset.mark,
              maxLines: 1,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: size * 0.36,
                height: 1,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

