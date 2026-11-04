/// 侧边会话抽屉：顶部搜索框 + 日期分组 + 纯文字条目 + 底部账号栏。
/// 布局对齐官方 App（docs/design-tokens.md 4.2 节：搜索框 y117..248 逐像素一致）。
library;

import 'package:flutter/material.dart';

import '../bridge/models.dart';
import '../design/tokens.dart';
import 'chat_state.dart';

class SessionsDrawer extends StatefulWidget {
  const SessionsDrawer({
    super.key,
    required this.state,
    required this.colors,
    required this.onOpenSettings,
    required this.onClose,
  });

  final ChatState state;
  final DsColors colors;
  final VoidCallback onOpenSettings;

  /// 推挤式抽屉不走 Navigator 路由，条目点选后用这个回调收起抽屉
  /// （原 Scaffold.drawer 方案里是 Navigator.pop，会在 Stack 实现下误弹聊天页）。
  final VoidCallback onClose;

  @override
  State<SessionsDrawer> createState() => SessionsDrawerState();
}

class SessionsDrawerState extends State<SessionsDrawer> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final c = widget.colors;
    // 官方抽屉：顶部搜索框（圆角胶囊灰底）→ 日期分组标题 → 会话条目 → 底部账号栏。
    final groups = state.sessionGroups;
    final q = _search.text.trim().toLowerCase();
    return Drawer(
      width: DsSpacing.drawerWidth,
      backgroundColor: c.bgLayer1,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DsSpacing.drawerSearchPadH,
                DsSpacing.drawerSearchPadTop,
                DsSpacing.drawerSearchPadRight,
                0,
              ),
              child: Container(
                height: DsSpacing.drawerSearchHeight,
                padding: const EdgeInsets.symmetric(
                  horizontal: DsSpacing.drawerSearchInset,
                ),
                decoration: BoxDecoration(
                  color: c.drawerSearchFill,
                  borderRadius: BorderRadius.circular(
                    DsSpacing.drawerSearchRadius,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 20, color: c.drawerGroupLabel),
                    const SizedBox(width: DsSpacing.drawerSearchIconGap),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        style: DsTypography.small.copyWith(
                          color: c.labelPrimary,
                        ),
                        cursorColor: c.brand,
                        decoration: InputDecoration(
                          hintText: '搜索对话内容...',
                          hintStyle: DsTypography.small.copyWith(
                            color: c.drawerGroupLabel,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: groups.isEmpty
                  ? Center(
                      child: Text(
                        '暂无会话',
                        style: DsTypography.small.copyWith(
                          color: c.drawerGroupLabel,
                        ),
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        for (final entry in groups.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              DsSpacing.drawerGroupPadH,
                              DsSpacing.drawerGroupPadV,
                              DsSpacing.drawerGroupPadH,
                              DsSpacing.drawerGroupGap,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  entry.key,
                                  style: DsTypography.small.copyWith(
                                    color: c.drawerGroupLabel,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.tune,
                                  size: 16,
                                  color: c.drawerGroupLabel,
                                ),
                              ],
                            ),
                          ),
                          for (final s in entry.value)
                            if (q.isEmpty ||
                                s.displayTitle.toLowerCase().contains(q))
                              SessionsDrawerItem(
                                session: s,
                                selected: s.id == state.sessionId,
                                colors: c,
                                onTap: () {
                                  widget.onClose();
                                  state.openSession(s);
                                },
                              ),
                        ],
                      ],
                    ),
            ),
            SessionsDrawerFooter(
              colors: c,
              label: state.deviceLabel,
              connectionLabel: state.connectionLabel,
              onOpenSettings: widget.onOpenSettings,
              onClose: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }
}

/// 单条会话：官方是纯文字行（选中态蓝字），无 card、无分割线。
class SessionsDrawerItem extends StatelessWidget {
  const SessionsDrawerItem({
    super.key,
    required this.session,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final DshSession session;
  final bool selected;
  final DsColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DsSpacing.drawerItemPadH,
          vertical: DsSpacing.drawerItemPadV,
        ),
        child: Text(
          session.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DsTypography.small.copyWith(
            color: selected ? colors.brand : colors.labelPrimary,
            height: DsSpacing.drawerLineHeight / 14,
          ),
        ),
      ),
    );
  }
}

/// 底部账号栏（真机反馈第三轮 3）：设置按钮 + 绿点连接指示 + 连接地址。
/// 原版是头像 + 设备名 + 三点菜单；改为「设置」圆钮为主操作，
/// 下方绿点（连接成功即亮）+ host:port 小字，一眼看清当前连的是哪台机器。
class SessionsDrawerFooter extends StatelessWidget {
  const SessionsDrawerFooter({
    super.key,
    required this.colors,
    required this.label,
    required this.connectionLabel,
    required this.onOpenSettings,
    required this.onClose,
  });

  final DsColors colors;
  final String label;

  /// 当前连接地址（host:port，来自 ChatState.connectionLabel）。
  final String connectionLabel;
  final VoidCallback onOpenSettings;

  /// 推挤式抽屉关闭回调（见 SessionsDrawer.onClose 注释）。
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.drawerFooterPadH,
        vertical: DsSpacing.drawerItemPadV,
      ),
      child: Row(
        children: [
          // 设置按钮（替代原头像/三点菜单，真机反馈第三轮 3）。
          Tooltip(
            message: '设置',
            child: InkResponse(
              onTap: () {
                onClose();
                onOpenSettings();
              },
              radius: 22,
              child: CircleAvatar(
                radius: 16,
                backgroundColor: colors.drawerSearchFill,
                child: Icon(
                  Icons.settings_outlined,
                  size: 18,
                  color: colors.labelPrimary,
                ),
              ),
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
                  style: DsTypography.base.copyWith(color: colors.labelPrimary),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // 绿点 = 连接正常（抽屉只在已连接状态可达）。
                        color: const Color(0xFF34C759),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        connectionLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DsTypography.caption
                            .copyWith(color: colors.labelSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
