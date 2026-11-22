/// 抽屉底部主机卡片（2026-11-22 对齐 dsh-go `sessions_drawer` 底部一行）：
/// 主机图标 + 设备名 + 「连接服务 · host:port」+ 连接状态点，右侧齿轮开设置。
///
/// 点色语义（真机反馈第五轮）：绿点 = 桥连接正常（GatewayState.ready），
/// 红点 = 未连接（connecting/closed/authFailed 等一切非 ready 态）。
/// 整行也可点——用户不必精确点到齿轮。
library;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';

class SessionsDrawerFooter extends StatelessWidget {
  const SessionsDrawerFooter({
    super.key,
    required this.colors,
    required this.label,
    required this.connectionLabel,
    required this.connected,
    required this.onOpenSettings,
    required this.onClose,
  });

  final DsColors colors;
  final String label;

  /// 当前连接地址（host:port，来自 ChatState.connectionLabel）。
  final String connectionLabel;

  /// 桥是否连接正常（GatewayState.ready）；false 显示红点。
  final bool connected;
  final VoidCallback onOpenSettings;

  /// 推挤式抽屉关闭回调（见 SessionsDrawer.onClose 注释）。
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.drawerToolbarPadH,
        8,
        DsSpacing.drawerToolbarPadH,
        10,
      ),
      child: Material(
        color: colors.drawerSearchFill,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            onClose();
            onOpenSettings();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                // 主机图标（dsh-go 用笔记本图标占左侧）。
                SizedBox.square(
                  dimension: DsSpacing.drawerRoundButtonSize,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.chipSelectedBg,
                    ),
                    child: Icon(Icons.computer, size: 18, color: colors.brand),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DsTypography.base.copyWith(
                          color: colors.labelPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: DsSpacing.drawerStatusDot,
                            height: DsSpacing.drawerStatusDot,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: connected
                                  ? const Color(0xFF34C759)
                                  : const Color(0xFFFF3B30),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '连接服务 · $connectionLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DsTypography.caption.copyWith(
                                color: colors.labelSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // dsh-go 底部还有一颗「四宫格」（应用启动器）——本仓没有应用
                // 抽屉这种东西，不放占位假入口；288dp 抽屉里它也把设备名挤断。
                IconButton(
                  tooltip: '设置',
                  icon: Icon(
                    Icons.settings_outlined,
                    size: 20,
                    color: colors.labelSecondary,
                  ),
                  onPressed: () {
                    onClose();
                    onOpenSettings();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
