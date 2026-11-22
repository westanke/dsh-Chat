/// 顶栏「更多」菜单：本地投影面板入口 + 会话导出（从 chat_page.dart 拆出，
/// 避免页面文件越过 AGENTS §7 的 500 行线）。
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../bridge/platform.dart';
import '../design/tokens.dart';
import 'chat_state.dart';
import 'model_sheet.dart';
import 'session_tabs_sheet.dart';

class ChatOverflowMenu extends StatelessWidget {
  const ChatOverflowMenu({
    super.key,
    required this.colors,
    required this.state,
  });

  final DsColors colors;
  final ChatState state;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return PopupMenuButton<String>(
      tooltip: '更多',
      icon: Icon(Icons.more_vert, size: 22, color: c.labelPrimary),
      color: c.settingsSurface,
      onSelected: (value) async {
        switch (value) {
          // 2026-11-22：原来分散的六个面板收进一个可左右滑动的 TAB 容器。
          case 'panels':
            await showSessionTabsSheet(
              context,
              state,
              c,
              onShare: () => _export(context, share: true),
            );
          case 'export':
            await _export(context, share: false);
          case 'share':
            await _export(context, share: true);
          case 'model':
            final sid = state.sessionId;
            if (sid == null || sid.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请先打开一个会话再调整模型')),
              );
              return;
            }
            final changed = await showModelSheet(
              context,
              colors: c,
              gateway: state.gateway,
              sessionId: sid,
            );
            if (changed) await state.reloadHistory();
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        _menuItem('panels', Icons.dashboard_customize_outlined, '会话面板'),
        _menuItem('model', Icons.tune, '调整模型'),
        if (state.sessionId != null && state.messages.isNotEmpty) ...[
          const PopupMenuDivider(),
          _menuItem('export', Icons.copy_all_outlined, '复制对话（Markdown）'),
          _menuItem('share', Icons.share_outlined, '分享对话（Markdown）'),
        ],
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 18, color: colors.labelSecondary),
            const SizedBox(width: DsSpacing.chipIconGap),
            Text(
              label,
              style: DsTypography.small.copyWith(color: colors.labelPrimary),
            ),
          ],
        ),
      );

  Future<void> _export(BuildContext context, {required bool share}) async {
    final body = sessionMarkdown(state);
    if (body.trim().isEmpty) return;
    if (share) {
      final ok = await DshPlatform.share(body);
      if (!ok && context.mounted) _toast(context, '系统分享不可用');
      return;
    }
    await Clipboard.setData(ClipboardData(text: body));
    if (context.mounted) _toast(context, '已复制 Markdown');
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

/// 把当前会话导出成 Markdown：只用已落库/流式中的正文，跳过过程组、
/// 错误行与命令回显（那些是运行痕迹，不是对话）。
String sessionMarkdown(ChatState state) {
  final buf = StringBuffer();
  final title = state.sessions
      .where((s) => s.id == state.sessionId)
      .map((s) => s.displayTitle)
      .where((t) => t.trim().isNotEmpty)
      .firstOrNull;
  buf.writeln('# ${title ?? '会话'}');
  buf.writeln();
  for (final m in state.messages) {
    final text = m.text.trim();
    if (text.isEmpty) continue;
    switch (m.role) {
      case 'user':
        buf
          ..writeln('## 我')
          ..writeln()
          ..writeln(text)
          ..writeln();
      case 'assistant':
        buf
          ..writeln('## 助手')
          ..writeln()
          ..writeln(text)
          ..writeln();
    }
  }
  return buf.toString();
}
