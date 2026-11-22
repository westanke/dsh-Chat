// 权限档位 chip：拉清单 → 底部弹层选档 → 需要时二次确认 → 调 setPermission。
// 从 composer.dart 拆出（宪法 §7 单文件 ≤500 行）；同为 composer.dart 的 part，
// 同库 part 可访问 ComposerState 私有成员，所以用 extension 承载。
part of 'composer.dart';

/// 权限档位与选图——两项都是输入条上的次级交互，放一起便于守 §7 行数。
extension _ComposerPermission on ComposerState {
  /// 「+」圆钮：弹附件面板（2026-11-22，对齐 dsh-Go `plus_panel.dart`）。
  /// 面板里选「相册」再走回 [_pickImage]、「文件」走 `@` 提及插入。
  Future<void> _openPlusPanel() async {
    final action = await showPlusPanel(
      context,
      colors: c,
      sessionId: widget.sessionId,
      permissionLabel: () => _plusPermissionValue,
      planEnabled: (widget.sessionId ?? '').isNotEmpty,
      onPickPermission: _pickPermission,
      onPlanChanged: _setPlanMode,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case PlusAction.album:
        await _pickImage();
      case PlusAction.files:
        _focus.requestFocus();
        insertAtMention(_controller, _onChanged);
    }
  }

  /// 面板「权限」行的取值：还没取到当前档位时写「默认」（否则读成「权限 权限」）。
  String get _plusPermissionValue =>
      (widget.currentPermission ?? '').isEmpty ? '默认' : _permissionLabel;

  /// 面板「计划模式」开关：命令走 `ChatState.runCommand`（`/plan` / `/plan off`，
  /// 与 dsh-Go `plus_panel.dart:285` 同一对内核命令，桥不拦截、整行透传）。
  ///
  /// 本仓 ChatState 还没折叠 `plan/mode` 投影（只有 `currentPermission`），读不回
  /// 服务端当前档位，所以开关的界面口径记在面板侧（plus_panel.dart 的
  /// `_planMemoValue`）：真实结果以命令卡（✓/✗）为准。
  void _setPlanMode(bool on) {
    if ((widget.sessionId ?? '').isEmpty) return;
    widget.onCommand(on ? '/plan' : '/plan off');
  }

  Future<void> _pickImage() async {
    final picked = await DshPlatform.pickImage();
    if (picked == null || !mounted) return;
    final resolved = await resolvePickedImage(picked);
    if (!mounted) return;
    if (resolved.error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(resolved.error!)));
      return;
    }
    final img = await pickComposerImage(picked, resolved.mediaType!);
    if (img == null || !mounted) return;
    if (_pendingImages.length >= ComposerState._maxImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('一条消息最多带 ${ComposerState._maxImages} 张图片')),
      );
      return;
    }
    _refresh(() => _pendingImages.add(img));
  }

  /// 拉取权限档位清单并弹出选择菜单（服务端是权威；失败给明确提示）。
  Future<void> _pickPermission() async {
    final gw = widget.gateway;
    if (gw == null || _loadingOptions) return;
    _refresh(() => _loadingOptions = true);
    List<PermissionOption> options;
    try {
      final raw = await gw.permissionOptionsRaw();
      options = parsePermissionCatalog(raw).switchable;
    } on RequestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('权限档位获取失败：${e.message}')));
      }
      return;
    } finally {
      if (mounted) _refresh(() => _loadingOptions = false);
    }
    if (!mounted || options.isEmpty) return;
    final selected = await showModalBottomSheet<PermissionOption>(
      context: context,
      constraints: modalSheetConstraints(context),
      backgroundColor: c.bgLayer1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DsSpacing.settingsCardRadius),
        ),
      ),
      builder: (context) => _PermissionSheet(
        colors: c,
        options: options,
        current: widget.currentPermission,
      ),
    );
    if (selected == null || !mounted) return;
    final sid = widget.sessionId;
    if (sid == null || sid.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先打开一个会话再切换权限档位')));
      return;
    }
    if (selected.needsConfirm) {
      final ok = await confirmFullPermission(context, c);
      if (ok != true || !mounted) return;
    }
    try {
      await widget.gateway!.setPermission(sid, selected.value);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('权限已切换为「${selected.label}」')));
      }
    } on RequestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('切换失败：${e.message}')));
      }
    }
  }
}
