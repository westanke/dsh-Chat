/// 通知设置（对齐 dsh-go 的 notification_settings）：总开关 + 四类事件开关 +
/// 系统权限状态与引导。part of settings_page.dart，共享 _Section/_ActionRow 等私有成员。
part of 'settings_page.dart';

/// 设置页里的「通知」入口行：显示当前能否弹通知，点进去细调。
class _NotifySection extends StatefulWidget {
  const _NotifySection({required this.colors});

  final DsColors colors;

  @override
  State<_NotifySection> createState() => _NotifySectionState();
}

class _NotifySectionState extends State<_NotifySection> {
  NotifyStatus? _status;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await DshNotify.status();
    if (mounted) setState(() => _status = s);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return _Section(
      colors: c,
      title: '通知',
      children: [
        _ActionRow(
          colors: c,
          icon: Icons.notifications_outlined,
          title: '通知',
          subtitle: _subtitle(),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => NotifySettingsPage(colors: c),
              ),
            );
            // 从系统设置回来后刷新权限状态。
            if (mounted) _refresh();
          },
        ),
      ],
    );
  }

  String _subtitle() {
    final s = _status;
    if (s == null) return '读取系统通知状态…';
    if (!s.native) return '当前平台不支持系统通知';
    if (!s.permission) return '通知权限未授予，去设置里开启';
    if (!s.enabled) return '系统已关闭本应用通知';
    return NotifyPrefs.instance.enabled ? '已开启：回答完成、等待审批时提醒' : '已关闭';
  }
}

/// 通知设置页：偏好开关 + 权限引导（Android 13+ 需运行时权限）。
class NotifySettingsPage extends StatefulWidget {
  const NotifySettingsPage({required this.colors, super.key});

  final DsColors colors;

  @override
  State<NotifySettingsPage> createState() => _NotifySettingsPageState();
}

class _NotifySettingsPageState extends State<NotifySettingsPage> {
  NotifyStatus? _status;

  @override
  void initState() {
    super.initState();
    DshNotify.init();
    DshNotify.ensureChannels();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await DshNotify.status();
    if (mounted) setState(() => _status = s);
  }

  /// 发一条测试通知：让用户当场确认「权限 + 通道」这条链路是通的。
  Future<void> _sendTest() async {
    final ok = await DshNotify.show(
      const NotifyPayload(
        title: '测试通知',
        text: '看到这条说明通知链路已打通；点它会回到设置页所在的会话。',
        key: 'selftest',
        attention: false,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已发送测试通知' : '发送失败，请检查系统通知权限')),
    );
  }

  Future<void> _askPermission() async {
    final ok = await DshNotify.requestPermission();
    await _refresh();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未获得通知权限，可到系统设置里手动开启')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final prefs = NotifyPrefs.instance;
    final status = _status;
    return Scaffold(
      backgroundColor: c.bgBase,
      appBar: AppBar(
        backgroundColor: c.bgBase,
        elevation: 0,
        title: Text(
          '通知',
          style: DsTypography.pageTitle.copyWith(color: c.labelPrimary),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: prefs,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: DsSpacing.settingsPadH,
              vertical: DsSpacing.settingsPadV,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: readableColumnWidth(MediaQuery.sizeOf(context).width),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Section(
                      colors: c,
                      title: '提醒内容',
                      children: [
                        _SwitchRow(
                          colors: c,
                          title: '允许通知',
                          description: '总开关：关掉后所有系统通知都不发（界面内卡片不受影响）。',
                          value: prefs.enabled,
                          onChanged: prefs.setEnabled,
                        ),
                        _SwitchRow(
                          colors: c,
                          title: '回答完成',
                          description: '一轮回答结束、任务做完时提醒。',
                          value: prefs.done,
                          onChanged: prefs.setDone,
                        ),
                        _SwitchRow(
                          colors: c,
                          title: '执行失败',
                          description: '本轮执行出错或被中断时提醒。',
                          value: prefs.failed,
                          onChanged: prefs.setFailed,
                        ),
                        _SwitchRow(
                          colors: c,
                          title: '等待审批',
                          description: '工具调用等你批准时提醒。',
                          value: prefs.approval,
                          onChanged: prefs.setApproval,
                        ),
                        _SwitchRow(
                          colors: c,
                          title: '提问待回答',
                          description: '模型向你提问、等你选择时提醒。',
                          value: prefs.question,
                          onChanged: prefs.setQuestion,
                        ),
                      ],
                    ),
                    const SizedBox(height: DsSpacing.settingsSectionGap),
                    _Section(
                      colors: c,
                      title: '系统权限',
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DsSpacing.settingsCardPadH,
                            vertical: DsSpacing.settingsCardPadV,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                status == null
                                    ? '读取中…'
                                    : !status.native
                                    ? '当前平台不支持系统通知'
                                    : status.canPost
                                    ? '已允许，通知可以正常弹出'
                                    : status.permission
                                    ? '系统已关闭本应用通知'
                                    : '未授予通知权限',
                                style: DsTypography.base.copyWith(
                                  color: c.labelPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '正在看的会话不会打扰；点通知会直接跳到对应会话。',
                                style: DsTypography.caption.copyWith(
                                  color: c.labelTertiary,
                                ),
                              ),
                              if (status != null && status.native && status.canPost) ...[
                                const SizedBox(height: 10),
                                TextButton(
                                  onPressed: _sendTest,
                                  child: Text(
                                    '发送测试通知',
                                    style: DsTypography.smallStrong.copyWith(
                                      color: c.brand,
                                    ),
                                  ),
                                ),
                              ],
                              if (status != null && status.native && !status.canPost) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    if (!status.permission)
                                      TextButton(
                                        onPressed: _askPermission,
                                        child: Text(
                                          '申请权限',
                                          style: DsTypography.smallStrong.copyWith(
                                            color: c.brand,
                                          ),
                                        ),
                                      ),
                                    TextButton(
                                      onPressed: () async {
                                        await DshNotify.openSettings();
                                        await _refresh();
                                      },
                                      child: Text(
                                        '去系统设置',
                                        style: DsTypography.smallStrong.copyWith(
                                          color: c.brand,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
