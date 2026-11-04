/// 检查新版本行（真机反馈 2026-11-04 第 9 项）。
/// 从 settings_sections.dart 拆出（宪法 §7 单文件 ≤500 行）；
/// part of settings_page.dart，共享 _appVersion/_Section/_ActionRow 私有成员。
part of 'settings_page.dart';

class _UpdateCheckRow extends StatefulWidget {
  const _UpdateCheckRow({required this.colors});

  final DsColors colors;

  @override
  State<_UpdateCheckRow> createState() => _UpdateCheckRowState();
}

class _UpdateCheckRowState extends State<_UpdateCheckRow> {
  bool _checking = false;
  String? _result; // 展示在 subtitle 的结果行
  ReleaseInfo? _latest; // 最近一次检查拿到的远端发布信息（有新版时用于下载）
  Timer? _silentTimer; // 静默检查延迟；dispose 时取消（测试断言无 pending timer）

  @override
  void initState() {
    super.initState();
    // 静默检查一次：只在「有新版」时打扰（应用打开后 1.5s）。
    _silentTimer = Timer(const Duration(milliseconds: 1500), _silentCheck);
  }

  @override
  void dispose() {
    _silentTimer?.cancel();
    super.dispose();
  }

  Future<void> _silentCheck() async {
    if (!mounted || _checking) return;
    final rel = await _fetchQuiet();
    if (!mounted || rel == null) return;
    if (isNewerVersion(rel.versionParts, _currentVersionParts)) {
      setState(() => _result = '发现新版本 ${rel.tag}');
    }
  }

  List<int> get _currentVersionParts {
    final v = _appVersion.split('+').first;
    final parts = v.split('.');
    return [
      for (var i = 0; i < 3; i++)
        i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0,
    ];
  }

  /// 拉最新发布信息；失败回 null（静默检查不打扰）。
  Future<ReleaseInfo?> _fetchQuiet() async {
    try {
      return await fetchLatestRelease();
    } on Exception {
      return null;
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _result = null;
      _latest = null;
    });
    try {
      final rel = await fetchLatestRelease();
      if (!mounted) return;
      if (isNewerVersion(rel.versionParts, _currentVersionParts)) {
        setState(() {
          _latest = rel;
          _result = '发现新版本 ${rel.tag}，点此下载';
        });
      } else {
        setState(() => _result = '已是最新版本（远端 ${rel.tag}）');
      }
    } on Exception {
      if (!mounted) return;
      setState(() => _result = '检查失败：Gitee / GitHub 都连不上');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// 下载新版 APK（系统下载器）+ 轮询进度 + 完成自动拉起安装
  /// （第二轮反馈 C：之前只回「已加入下载」，无进度、装不装成功无从判断）。
  Future<void> _download(ReleaseInfo rel) async {
    final id = await DshPlatform.downloadApk(rel.apkUrl, rel.apkName);
    if (!mounted) return;
    if (id <= 0) {
      setState(() => _result = '下载任务创建失败');
      return;
    }
    setState(() => _result = '下载中… 0%');
    // 轮询 DownloadManager 状态：1s 间隔，进度更新 subtitle；完成后自动安装。
    // 不用 Timer.periodic 挂 dispose（测试断言无 pending timer），每轮 await
    // 后检查 mounted，页面关掉轮询自然停止。
    while (mounted) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      final st = await DshPlatform.downloadStatus(id);
      if (!mounted) return;
      if (st == null) {
        setState(() => _result = '下载状态不可用（可在系统通知栏查看）');
        return;
      }
      final status = st['status'] ?? 0;
      if (status == 8) {
        // STATUS_SUCCESSFUL → 拉起安装
        final launched = await DshPlatform.installApk(id);
        if (!mounted) return;
        setState(() {
          _result = launched
              ? '下载完成，已拉起安装；若未弹出，点系统通知安装'
              : '下载完成：${rel.apkName}（点系统通知安装）';
        });
        return;
      }
      if (status == 16) {
        setState(() => _result = '下载失败（网络或存储）；可回设置重试');
        return;
      }
      final total = st['total'] ?? 0;
      final done = st['bytes'] ?? 0;
      final pct = total > 0 ? (done * 100 ~/ total) : null;
      setState(() {
        _result = pct != null ? '下载中… $pct%' : '下载中… ${done ~/ 1024}KB';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final result = _result;
    final hasNew = result != null && result.startsWith('发现新版本');
    final latest = _latest;
    return _ActionRow(
      colors: c,
      icon: _checking
          ? Icons.hourglass_empty
          : hasNew
          ? Icons.system_update_alt
          : Icons.update_outlined,
      title: hasNew ? result : '检查更新',
      subtitle: _checking
          ? '正在检查（Gitee → GitHub）…'
          : result ?? '当前 $_appVersion · 国内走 Gitee、国外走 GitHub',
      onTap: _checking
          ? () {}
          : hasNew && latest != null
          ? () => _download(latest)
          : _check,
    );
  }
}

// ---------- 断开连接 ----------

class _DisconnectSection extends StatelessWidget {
  const _DisconnectSection({
    required this.colors,
    required this.onDisconnect,
  });

  final DsColors colors;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.only(
        top: DsSpacing.settingsSectionGap,
        bottom: DsSpacing.settingsSectionGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            onPressed: () => _confirm(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.danger,
              side: BorderSide(color: c.danger),
              minimumSize: const Size.fromHeight(50),
              shape: const StadiumBorder(),
            ),
            child: Text(
              '断开连接',
              style: DsTypography.baseStrong.copyWith(color: c.danger),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '将断开当前连接、清除本机配对并回到连接页；下次启动需重新输入配对码。',
            style: DsTypography.caption.copyWith(color: c.labelTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final c = colors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: c.settingsSurface,
        title: Text(
          '断开连接？',
          style: DsTypography.h4.copyWith(color: c.labelPrimary),
        ),
        content: Text(
          '本机配对信息会被清除，需要重新输入配对码才能再次连接。',
          style: DsTypography.small.copyWith(color: c.labelSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              '取消',
              style: DsTypography.small.copyWith(color: c.labelPrimary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              '断开',
              style: DsTypography.smallStrong.copyWith(color: c.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await onDisconnect();
    if (context.mounted) Navigator.of(context).pop();
  }
}
