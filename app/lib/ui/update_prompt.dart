/// 启动时检查更新，有新版就弹「是否下载」（用户 2026-11-22 第 3 项需求）。
///
/// 背景：`release_check.dart` 早就能查 Gitee/GitHub Release，但入口只在设置页
/// 里静默检查一次、只改一行副标题——用户不点设置就永远不知道有新版本。
/// 这里把它提到启动路径：发现新版直接弹对话框，问「是否下载」。
///
/// 打扰控制：同一版本点「稍后」后不再弹（`update.skippedVersion`），
/// 下次发版（tag 变了）重新提示。下载走原生 DownloadManager（零权限），
/// 完成后自动拉起安装（与设置页同一套平台通道）。
library;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bridge/dlog.dart';
import '../bridge/platform.dart';
import '../bridge/release_check.dart';
import '../design/tokens.dart';

/// 用户点过「稍后」的版本 tag；同 tag 不再打扰。
const updateSkippedKey = 'update.skippedVersion';

/// 本机版本三段的纯函数（`1.0.27+28` → [1,0,27]；脏值按段补 0）。
List<int> versionPartsOf(String version) {
  final core = version.split('+').first.split('.');
  return [
    for (var i = 0; i < 3; i++)
      i < core.length ? int.tryParse(core[i]) ?? 0 : 0,
  ];
}

/// 是否需要提示更新（纯逻辑，便于单测）。
bool shouldPromptUpdate({
  required String localVersion,
  required ReleaseInfo latest,
  String? skippedTag,
}) {
  if (localVersion.isEmpty || skippedTag == latest.tag) return false;
  return isNewerVersion(latest.versionParts, versionPartsOf(localVersion));
}

/// 启动后调用（须在 Navigator 就绪后，一般由 `addPostFrameCallback` 触发）。
/// 静默失败：网络不通/版本读不到都不打扰启动流程。
Future<void> checkUpdateOnLaunch(BuildContext context) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  final local = await DshPlatform.appVersion();
  if (local == null || local.isEmpty) return;
  final ReleaseInfo latest;
  try {
    latest = await fetchLatestRelease();
  } on Exception catch (e) {
    DshLog.w('update check failed: $e');
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  if (!shouldPromptUpdate(
    localVersion: local,
    latest: latest,
    skippedTag: prefs.getString(updateSkippedKey),
  )) {
    return;
  }
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _UpdatePromptDialog(
      latest: latest,
      localVersion: local,
      colors: DsColors(Theme.of(dialogContext).brightness == Brightness.dark),
    ),
  );
  if (ok != true) {
    await prefs.setString(updateSkippedKey, latest.tag);
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => UpdateDownloadDialog(
      release: latest,
      colors: DsColors(Theme.of(dialogContext).brightness == Brightness.dark),
    ),
  );
}

class _UpdatePromptDialog extends StatelessWidget {
  const _UpdatePromptDialog({
    required this.latest,
    required this.localVersion,
    required this.colors,
  });

  final ReleaseInfo latest;
  final String localVersion;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final size = latest.size;
    final sizeText = size == null ? '' : ' · ${(size / 1048576).toStringAsFixed(1)}MB';
    final notes = _shortNotes(latest.notes);
    return AlertDialog(
      backgroundColor: c.settingsSurface,
      title: Text(
        '发现新版本 ${latest.tag}',
        style: DsTypography.h4.copyWith(color: c.labelPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前 ${localVersion.split('+').first} → ${latest.tag}$sizeText',
            style: DsTypography.small.copyWith(color: c.labelSecondary),
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              notes,
              style: DsTypography.caption.copyWith(color: c.labelTertiary),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '下载后会自动拉起安装；也可以稍后到「设置 → 检查更新」里再来一次。',
            style: DsTypography.caption.copyWith(color: c.labelTertiary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            '稍后',
            style: DsTypography.small.copyWith(color: c.labelSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            '下载更新',
            style: DsTypography.smallStrong.copyWith(color: c.brand),
          ),
        ),
      ],
    );
  }

  /// 发布正文压成一段纯文本（Markdown 标记只做最小清理），最多 240 字。
  String _shortNotes(String? raw) {
    if (raw == null) return '';
    final flat = raw
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'[#>*`|-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return flat.length <= 240 ? flat : '${flat.substring(0, 240)}…';
  }
}

/// 下载进度对话框：创建任务 → 每秒轮询 → 成功顺手拉起安装。
class UpdateDownloadDialog extends StatefulWidget {
  const UpdateDownloadDialog({
    required this.release,
    required this.colors,
    super.key,
  });

  final ReleaseInfo release;
  final DsColors colors;

  @override
  State<UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<UpdateDownloadDialog> {
  double? _pct;
  String _status = '正在创建下载任务…';
  bool _finished = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final id = await DshPlatform.downloadApk(
      widget.release.apkUrl,
      widget.release.apkName,
    );
    if (!mounted) return;
    if (id <= 0) {
      setState(() {
        _status = '下载任务创建失败，可稍后到设置页重试';
        _failed = true;
      });
      return;
    }
    setState(() => _status = '下载中… 0%');
    while (mounted) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      final st = await DshPlatform.downloadStatus(id);
      if (!mounted) return;
      if (st == null) {
        setState(() {
          _status = '下载状态不可用（可在系统通知栏查看进度）';
          _failed = true;
        });
        return;
      }
      final status = st['status'] ?? 0;
      if (status == 8) {
        final launched = await DshPlatform.installApk(id);
        if (!mounted) return;
        setState(() {
          _status = launched
              ? '下载完成，已拉起安装；若没弹出请点系统通知安装'
              : '下载完成：可点系统通知安装';
          _pct = 1;
          _finished = true;
        });
        return;
      }
      if (status == 16) {
        setState(() {
          _status = '下载失败（网络或存储），可稍后重试';
          _failed = true;
        });
        return;
      }
      final total = st['total'] ?? 0;
      final done = st['bytes'] ?? 0;
      setState(() {
        _pct = total > 0 ? (done / total).clamp(0.0, 1.0) : null;
        _status = total > 0
            ? '下载中… ${(done * 100 ~/ total)}%'
            : '下载中… ${done ~/ 1024}KB';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return AlertDialog(
      backgroundColor: c.settingsSurface,
      title: Text(
        _finished ? '下载完成' : '下载 ${widget.release.tag}',
        style: DsTypography.h4.copyWith(color: c.labelPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_failed) ...[
            LinearProgressIndicator(
              value: _finished ? 1.0 : _pct,
              minHeight: 6,
              backgroundColor: c.bgLayer1,
              color: c.brand,
            ),
            const SizedBox(height: 10),
          ],
          Text(
            _status,
            style: DsTypography.small.copyWith(
              color: _failed ? c.danger : c.labelSecondary,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            _finished || _failed ? '关闭' : '后台下载',
            style: DsTypography.smallStrong.copyWith(color: c.labelPrimary),
          ),
        ),
      ],
    );
  }
}
