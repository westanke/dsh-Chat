/// 会话长按操作（重命名 / 归档）：从 sessions_drawer.dart 拆出控行数。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../bridge/models.dart';
import '../design/tokens.dart';
import 'chat_state.dart';

/// 长按会话：重命名 / 归档（对照 dsh-go 会话长按菜单的常用两项）。
/// 归档/改名失败只在当前页 SnackBar 说明，不改本地列表——真值以服务端应答为准，
/// 动作成功后 `loadSessions()` 重拉。
Future<void> openSessionMenu(
  BuildContext context,
  ChatState state,
  DshSession session,
  DsColors c,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: c.bgLayer1,
    builder: (sheet) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              session.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DsTypography.small.copyWith(color: c.labelSecondary),
            ),
          ),
          ListTile(
            leading: Icon(Icons.edit_outlined, color: c.labelPrimary),
            title: Text('重命名', style: DsTypography.base.copyWith(color: c.labelPrimary)),
            onTap: () => Navigator.of(sheet).pop('rename'),
          ),
          ListTile(
            leading: Icon(Icons.call_split, color: c.labelPrimary),
            title: Text(
              '分叉到新会话',
              style: DsTypography.base.copyWith(color: c.labelPrimary),
            ),
            subtitle: Text(
              '带上当前对话，分叉后各自继续',
              style: DsTypography.caption.copyWith(color: c.labelTertiary),
            ),
            onTap: () => Navigator.of(sheet).pop('fork'),
          ),
          ListTile(
            leading: Icon(Icons.archive_outlined, color: c.danger),
            title: Text('归档会话', style: DsTypography.base.copyWith(color: c.danger)),
            subtitle: Text(
              '从列表隐藏，记录仍保留',
              style: DsTypography.caption.copyWith(color: c.labelTertiary),
            ),
            onTap: () => Navigator.of(sheet).pop('archive'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  if (action == 'rename') {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: session.displayTitle),
    );
    if (title == null || !context.mounted) return;
    try {
      await state.gateway.renameSession(session.id, title);
      await state.loadSessions();
    } on RequestException catch (e) {
      if (context.mounted) _toast(context, '重命名失败：${e.message}');
    }
    return;
  }

  if (action == 'fork') {
    try {
      final forked = await state.gateway.forkSession(session.id);
      await state.loadSessions();
      final created = state.sessions.where((s) => s.id == forked).firstOrNull;
      if (created != null) {
        await state.openSession(created);
      } else if (context.mounted) {
        _toast(context, '已分叉，但新会话还没出现在清单里');
      }
    } on RequestException catch (e) {
      if (context.mounted) _toast(context, '分叉失败：${e.message}');
    }
    return;
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('归档会话？'),
      content: Text(session.displayTitle, maxLines: 3, overflow: TextOverflow.ellipsis),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: c.danger,
            foregroundColor: c.onBrand,
          ),
          onPressed: () => Navigator.of(dialog).pop(true),
          child: const Text('归档'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await state.gateway.archiveSession(session.id);
    if (state.sessionId == session.id) await state.newChat();
    await state.loadSessions();
  } on RequestException catch (e) {
    if (context.mounted) _toast(context, '归档失败：${e.message}');
  }
}

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// 修剪会话标题：去首尾空白；空 → null（不可保存）；超长按 80 字截断
/// （桌面端重命名上限同口径；ws-sessions 不校验长度，客户端自己收敛）。
String? normalizeSessionTitle(String raw) {
  final title = raw.trim();
  if (title.isEmpty) return null;
  return title.length <= 80 ? title : title.substring(0, 80);
}

/// 重命名对话框：预填原标题，空白不能保存。
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection.collapsed(offset: widget.initial.length);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = normalizeSessionTitle(_controller.text);
    return AlertDialog(
      title: const Text('重命名会话'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (v) {
          final t = normalizeSessionTitle(v);
          if (t != null) Navigator.of(context).pop(t);
        },
        decoration: const InputDecoration(hintText: '会话标题'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: title == null
              ? null
              : () => Navigator.of(context).pop(title),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
