/// 抽屉顶部工具条（2026-11-22 对齐 dsh-go `sessions_drawer.dart` 顶部一行）：
/// 左侧品牌标 + 两个圆钮（工作区 / 换主机），右侧品牌色胶囊「新对话」。
///
/// 圆钮只做我们真有的能力：层叠 → 新建会话时的目录选择，交换 → 连接页
/// （换主机）。没有对应动作的按钮不放，避免假按钮。
library;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';
import 'brand_mark.dart';

class DrawerToolbar extends StatelessWidget {
  const DrawerToolbar({
    super.key,
    required this.colors,
    required this.onNewChat,
    required this.onSwitchHost,
  });

  final DsColors colors;
  final VoidCallback onNewChat;

  final VoidCallback onSwitchHost;

  /// 圆钮：直径固定 36（dsh-go DrawerViewButton.size），图标 20。
  Widget _round(IconData icon, String label, VoidCallback onTap) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: colors.drawerSearchFill,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(
              dimension: DsSpacing.drawerRoundButtonSize,
              child: Icon(icon, size: 20, color: colors.labelPrimary),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: DsSpacing.drawerToolbarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DsSpacing.drawerToolbarPadH,
        ),
        child: Row(
          children: [
            // 品牌标 + 字标（本仓自有品牌名，不写官方产品名）。
            DsBrandMark(
              color: colors.brandMark,
              bellyColor: colors.bgLayer1,
              width: DsSpacing.drawerToolbarHeight * 0.5,
              height: DsSpacing.drawerToolbarHeight * 0.4,
            ),
            // 手机抽屉只有 288 宽（系统字体放大时更紧）：品牌区放 Expanded
            // 里可收缩，「新对话」胶囊固定在右端永不被挤出边界。
            Expanded(
              child: Row(
                children: [
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'dsh-Chat',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DsTypography.smallStrong.copyWith(
                        color: colors.labelPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: DsSpacing.drawerToolbarGap),
                  // 手机抽屉只留「切换主机」一个圆钮。工作区范围由下面
                  // 「全部对话 ⌄」那一行管，不再重复放按钮。
                  _round(Icons.swap_horiz, '切换主机', onSwitchHost),
                ],
              ),
            ),
            _NewChatCapsule(colors: colors, onTap: onNewChat),
          ],
        ),
      ),
    );
  }
}

/// 品牌色胶囊「新对话」（dsh-go 同一位置、同一形状）。
class _NewChatCapsule extends StatelessWidget {
  const _NewChatCapsule({required this.colors, required this.onTap});

  final DsColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '新对话',
      child: Material(
        color: colors.brand,
        borderRadius: BorderRadius.circular(
          DsSpacing.drawerNewChatHeight / 2,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: DsSpacing.drawerNewChatHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DsSpacing.drawerNewChatPadH,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: colors.onBrand,
                  ),
                  const SizedBox(width: DsSpacing.drawerNewChatIconGap),
                  Text(
                    '新对话',
                    style: DsTypography.small.copyWith(
                      color: colors.onBrand,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
