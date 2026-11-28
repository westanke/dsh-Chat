/// 会话工作区文件的「打开 / 预览 / 分享」共用入口。
///
/// 产物卡（ArtifactCard）与交付卡（DeliverablesCard）都从桥的 REST
/// 文件面取字节：resolve 拿 rootId/contentType，readContent 拿字节，
/// 再交给系统查看器或系统分享。Markdown 走 App 内全屏渲染页。
///
/// 这里刻意收成一处：两套卡片的打开链此前各写一遍，行为已经出现分叉
/// （交付卡能打开、产物卡只能复制路径），再复制第三份只会继续漂移。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../bridge/platform.dart';
import '../design/tokens.dart';
import 'md_viewer.dart';

bool _isMarkdown(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.md') || lower.endsWith('.markdown');
}

/// 打开文件：md 进 App 内渲染页；其他交给系统「打开方式」。
///
/// 系统没有可打开的应用时，退回「分享真文件」而不是死交互；
/// 分享也不可用时只提示，不抛异常。
Future<void> openWorkspaceFile(
  BuildContext context, {
  required GatewayClient gateway,
  required String path,
  required String name,
  required DsColors colors,
}) async {
  if (_isMarkdown(path)) {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MdViewerPage(
          gateway: gateway,
          absolutePath: path,
          title: name,
          colors: colors,
        ),
      ),
    );
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  try {
    final resolved = await gatewayResolvePath(gateway, path);
    final bytes =
        await gatewayReadFileBytes(gateway, resolved.rootId, resolved.path);
    final opened = await DshPlatform.openFile(
      name: name,
      bytes: bytes,
      mime: resolved.contentType,
    );
    if (opened) return;
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('没有可打开此文件的应用，改为分享')),
    );
    await shareWorkspaceFile(
      context,
      gateway: gateway,
      path: path,
      name: name,
    );
  } on RequestException {
    _warn(messenger, '文件读取失败');
  } on Exception {
    _warn(messenger, '打开失败');
  }
}

/// 分享工作区文件（真文件字节，不是路径文本）。
///
/// 平台通道不支持文件分享时，退回分享路径并明确说明是路径，避免
/// 用户以为对方收到了文件。
Future<void> shareWorkspaceFile(
  BuildContext context, {
  required GatewayClient gateway,
  required String path,
  required String name,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final resolved = await gatewayResolvePath(gateway, path);
    final bytes =
        await gatewayReadFileBytes(gateway, resolved.rootId, resolved.path);
    final shared = await DshPlatform.shareFile(
      name: name,
      bytes: bytes,
      mime: resolved.contentType,
    );
    if (!messenger.mounted) return;
    if (shared) return;
    await _fallbackSharePath(messenger, path, '当前平台不支持文件分享，已改为分享路径');
  } on Exception {
    await _fallbackSharePath(messenger, path, '文件读取失败，已改为分享路径');
  }
}

Future<void> _fallbackSharePath(
  ScaffoldMessengerState messenger,
  String path,
  String tip,
) async {
  final ok = await DshPlatform.share(path);
  if (!messenger.mounted) return;
  messenger.showSnackBar(SnackBar(content: Text(ok ? tip : '分享暂不可用')));
}

void _warn(ScaffoldMessengerState messenger, String text) {
  if (!messenger.mounted) return;
  messenger.showSnackBar(SnackBar(content: Text(text)));
}
