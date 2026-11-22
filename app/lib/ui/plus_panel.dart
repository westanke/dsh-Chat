/// 「+」附件面板（对齐 dsh-Go `app/lib/ui/chat/widgets/plus_panel.dart`）。
///
/// 只列本仓**真能跑**的格子，宁缺勿假：
/// - `相册` → 系统相册选图，复用输入条原来的 `DshPlatform.pickImage` 通路；
/// - `文件` → 「选择项目中的内容」，复用输入条的 `@` 提及插入；
/// - dsh-Go 的 `拍照`（本仓原生通道只有 `pickImage`，没有相机 Intent）、
///   `生成`、`语音通话` 没有对应能力，一律不放；
/// - `手机操控 · 确认方式` 是 dsh-Go 的原生 `setPolicies`，本仓没有，整块不放。
///
/// 分组卡片：
/// - `本对话`：`权限`（叠一层既有档位 sheet）+ `计划模式`（`/plan` / `/plan off`）。
library;

import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';
import 'window_class.dart';

/// 「计划模式」开关的上次口径：本仓 ChatState 还没折叠 `plan/mode` 投影（只有
/// `currentPermission`），读不回服务端当前档位，所以面板记「本会话最近一次发出的
/// 命令」；命令（`/plan` / `/plan off`）才是唯一真源，结果以命令卡 ✓/✗ 为准。
/// 换会话即作废（只留一条，不按会话攒表）。
String? _planMemoSession;
bool _planMemoValue = false;

/// 宫格里被点中的格子：面板关掉后由调用方落到真实动作上。
enum PlusAction {
  /// 系统相册选图。
  album,

  /// 选择项目中的内容（`@` 提及）。
  files,
}

/// 弹出附件面板。返回用户点中的格子；直接关掉返回 null。
///
/// [onPickPermission] 与 [onPlanChanged] 在面板内部即时生效（与 dsh-Go 一致：
/// 权限行叠一层档位 sheet、计划模式行当场发命令），不关闭面板。
Future<PlusAction?> showPlusPanel(
  BuildContext context, {
  required DsColors colors,
  required String? sessionId,
  required String Function() permissionLabel,
  required bool planEnabled,
  required Future<void> Function() onPickPermission,
  required ValueChanged<bool> onPlanChanged,
}) {
  return showModalBottomSheet<PlusAction>(
    context: context,
    constraints: modalSheetConstraints(context),
    backgroundColor: colors.bgLayer1,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(DsSpacing.settingsCardRadius),
      ),
    ),
    builder: (sheetContext) => _PlusPanelBody(
      colors: colors,
      sessionId: sessionId,
      permissionLabel: permissionLabel,
      planEnabled: planEnabled,
      onPickPermission: onPickPermission,
      onPlanChanged: onPlanChanged,
    ),
  );
}

class _PlusPanelBody extends StatefulWidget {
  const _PlusPanelBody({
    required this.colors,
    required this.sessionId,
    required this.permissionLabel,
    required this.planEnabled,
    required this.onPickPermission,
    required this.onPlanChanged,
  });

  final DsColors colors;
  final String? sessionId;
  final String Function() permissionLabel;
  final bool planEnabled;
  final Future<void> Function() onPickPermission;
  final ValueChanged<bool> onPlanChanged;

  @override
  State<_PlusPanelBody> createState() => _PlusPanelBodyState();
}

class _PlusPanelBodyState extends State<_PlusPanelBody> {
  late bool _plan = _planMemoValue && _planMemoSession == widget.sessionId;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _handle(c),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DsPlusPanel.side,
                DsPlusPanel.tilesTop,
                DsPlusPanel.side,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _PlusTile(
                      colors: c,
                      icon: Icons.photo_library_outlined,
                      label: '相册',
                      background: c.plusAlbumBg,
                      foreground: c.plusAlbumFg,
                      onTap: () =>
                          Navigator.of(context).pop(PlusAction.album),
                    ),
                  ),
                  const SizedBox(width: DsPlusPanel.gap),
                  Expanded(
                    child: _PlusTile(
                      colors: c,
                      icon: Icons.folder_open_outlined,
                      label: '文件',
                      background: c.plusFilesBg,
                      foreground: c.plusFilesFg,
                      onTap: () =>
                          Navigator.of(context).pop(PlusAction.files),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DsPlusPanel.cardGap),
            _card(c, '本对话', [
              _PlusRow(
                colors: c,
                title: '权限',
                value: widget.permissionLabel(),
                // 叠一层档位 sheet：换完回到面板，重读当前档位（面板不关）。
                onTap: () async {
                  await widget.onPickPermission();
                  if (mounted) setState(() {});
                },
              ),
              _PlusSwitchRow(
                colors: c,
                title: '计划模式',
                value: _plan,
                enabled: widget.planEnabled,
                onChanged: (next) {
                  setState(() {
                    _plan = next;
                    _planMemoSession = widget.sessionId;
                    _planMemoValue = next;
                  });
                  widget.onPlanChanged(next);
                },
              ),
            ]),
            const SizedBox(height: DsPlusPanel.bottomPad),
          ],
        ),
      ),
    );
  }

  /// 顶部拖拽把手（纯装饰；sheet 本身已可下拉关闭）。
  Widget _handle(DsColors c) {
    return Padding(
      padding: const EdgeInsets.only(
        top: DsPlusPanel.handleTop,
        bottom: DsPlusPanel.handleBottom,
      ),
      child: Center(
        child: Container(
          width: DsPlusPanel.handleWidth,
          height: DsPlusPanel.handleHeight,
          decoration: BoxDecoration(
            color: c.borderL2,
            borderRadius: BorderRadius.circular(DsPlusPanel.handleHeight / 2),
          ),
        ),
      ),
    );
  }

  /// 分组卡片：小标题 + 圆角卡片（同设置页分区观感）。
  Widget _card(DsColors c, String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DsPlusPanel.side),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: DsPlusPanel.cardTitlePadH,
              bottom: DsPlusPanel.cardTitleGap,
            ),
            child: Text(
              title,
              style: DsTypography.smallStrong.copyWith(
                color: c.labelSecondary,
              ),
            ),
          ),
          Material(
            color: c.settingsSurface,
            borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ],
      ),
    );
  }
}

/// 宫格单格：彩色圆角方块 + 图标 + 下方文字（dsh-Go `PlusTile`）。
class _PlusTile extends StatelessWidget {
  const _PlusTile({
    required this.colors,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final DsColors colors;
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DsPlusPanel.tileRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DsPlusPanel.tilePadV),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: DsPlusPanel.tileSize,
                height: DsPlusPanel.tileSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius:
                      BorderRadius.circular(DsPlusPanel.tileRadius),
                ),
                child: Icon(
                  icon,
                  size: DsPlusPanel.tileIconSize,
                  color: foreground,
                ),
              ),
              const SizedBox(height: DsPlusPanel.tileLabelGap),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DsTypography.small.copyWith(
                  color: colors.labelSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片里的一行：标题 + 右侧取值 + ›。
class _PlusRow extends StatelessWidget {
  const _PlusRow({
    required this.colors,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final DsColors colors;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: DsSpacing.settingsRowMinHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DsSpacing.settingsCardPadH,
          ),
          child: Row(
            children: [
              Text(
                title,
                style: DsTypography.base.copyWith(color: c.labelPrimary),
              ),
              const SizedBox(width: DsPlusPanel.rowGap),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: DsTypography.small.copyWith(color: c.labelTertiary),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: DsPlusPanel.chevronSize,
                color: c.labelTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片里的开关行：整行可点（点标题也切），开关本身也可点。
class _PlusSwitchRow extends StatelessWidget {
  const _PlusSwitchRow({
    required this.colors,
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final DsColors colors;
  final String title;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final onChangedOrNull = enabled ? onChanged : null;
    return MergeSemantics(
      child: InkWell(
        onTap: onChangedOrNull == null ? null : () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: DsSpacing.settingsRowMinHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DsSpacing.settingsCardPadH,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: DsTypography.base.copyWith(
                      color: enabled ? c.labelPrimary : c.labelTertiary,
                    ),
                  ),
                ),
                Switch(
                  value: value,
                  onChanged: onChangedOrNull,
                  activeThumbColor: c.brand,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
