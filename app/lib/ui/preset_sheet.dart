/// 模式（Agent 预设）选择面板（问题1：＋号面板里选模式）。
///
/// 数据源：REST `GET /api/v1/chat/agent-presets`（chat.read scope，
/// gateway_rest.dart:293-327）。桥端限制：预设只在**空白会话**可切
/// （ws-chat/models-commands.ts 的 `selectAgentPreset` 对非 blank 会话抛
/// 409 `AGENT_PRESET_LOCKED`）—— 所以：
/// - 已有会话：面板只让切（失败由调用方提示「仅空白会话可切换」）。
/// - 还没有会话：只回选中的预设，由调用方在建会话时随 `session-create`
///   的 `agentPreset` 字段下发（bridge ws-sessions.ts:49-95 支持该字段）。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../design/tokens.dart';
import 'window_class.dart';

/// 弹出模式选择面板。返回用户选中的预设；取消返回 null。
Future<GatewayAgentPreset?> showPresetSheet(
  BuildContext context, {
  required DsColors colors,
  required GatewayClient gateway,
  required List<GatewayAgentPreset> presets,
  String? sessionId,
  String? currentPresetId,
}) async {
  final selected = await showModalBottomSheet<GatewayAgentPreset>(
    context: context,
    constraints: modalSheetConstraints(context),
    backgroundColor: colors.bgLayer1,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(DsSpacing.settingsCardRadius),
      ),
    ),
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(DsSpacing.settingsCardPadH),
              child: Text(
                '选择模式',
                style: DsTypography.baseStrong.copyWith(
                  color: colors.labelPrimary,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final p in presets)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        currentPresetId == p.id
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        size: 20,
                        color: currentPresetId == p.id
                            ? colors.brand
                            : colors.labelTertiary,
                      ),
                      title: Text(
                        p.name,
                        style: DsTypography.base.copyWith(
                          color: p.available
                              ? colors.labelPrimary
                              : colors.labelTertiary,
                        ),
                      ),
                      subtitle: p.description == null
                          ? null
                          : Text(
                              p.description!,
                              style: DsTypography.small.copyWith(
                                color: colors.labelTertiary,
                              ),
                            ),
                      onTap: p.available
                          ? () => Navigator.of(sheetContext).pop(p)
                          : null,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return selected;
}
