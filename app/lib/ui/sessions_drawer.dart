/// 侧边会话抽屉：顶部搜索框 + 日期分组 + 纯文字条目 + 底部账号栏。
/// 布局对齐官方 App（docs/design-tokens.md 4.2 节：搜索框 y117..248 逐像素一致）。
library;

import 'package:flutter/material.dart';

import '../bridge/models.dart';
import '../design/tokens.dart';
import 'chat_state.dart';

class SessionsDrawer extends StatefulWidget {
  const SessionsDrawer({super.key, required this.state, required this.colors});

  final ChatState state;
  final DsColors colors;

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
                                  Navigator.pop(context);
                                  state.openSession(s);
                                },
                              ),
                        ],
                      ],
                    ),
            ),
            SessionsDrawerFooter(colors: c, label: state.deviceLabel),
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

/// 底部账号栏：官方是头像 + 手机号 + 三点菜单（我们显示 bridge 设备名）。
class SessionsDrawerFooter extends StatelessWidget {
  const SessionsDrawerFooter({
    super.key,
    required this.colors,
    required this.label,
  });

  final DsColors colors;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.drawerFooterPadH,
        vertical: DsSpacing.drawerItemPadV,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: colors.drawerSearchFill,
            child: Icon(
              Icons.person_outline,
              size: 18,
              color: colors.drawerGroupLabel,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DsTypography.base.copyWith(color: colors.labelPrimary),
            ),
          ),
          Icon(Icons.more_horiz, size: 20, color: colors.drawerGroupLabel),
        ],
      ),
    );
  }
}
