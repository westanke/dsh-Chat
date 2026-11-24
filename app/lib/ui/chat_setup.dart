/// 新会话的配置入口（问题1：新建会话时模型 / 模式 / 权限都要能先选）。
///
/// 协议层没有「建会话时带模型 / 权限」的帧：bridge 的 `session-create` 只吃
/// `rootId / cwd / workspaceId / agentPreset / reuseBlank`（ws-sessions.ts:49-95），
/// 会话维度的模型与权限只有 `select-model` / `permission` 两帧，都要会话号。
/// 所以客户端走「先选 → 建会话 → 补应用」两步：草稿存在 [ChatSetupDraft]
/// （chat_setup_draft.dart），会话建好后由 [applyChatSetup] 补发那两帧；
/// 模式（Agent 预设）随 `session-create` 的 `agentPreset` 字段下发。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../design/tokens.dart';
import 'chat_state.dart';
import 'model_sheet.dart';
import 'preset_sheet.dart';

/// 选模型：已有会话直接切（服务端回传的那份为准）；还没有会话就记成草稿
///（建会话后补应用）。
///
/// 返回 true 表示「有变化」，调用方据此刷新历史 / 模型文案。
Future<bool> pickSessionModel(
  BuildContext context,
  ChatState state,
  DsColors colors,
) async {
  final sid = state.sessionId;
  final picked = await showModelSheet(
    context,
    colors: colors,
    gateway: state.gateway,
    sessionId: sid,
  );
  if (picked == null) return false;
  if (sid == null || sid.isEmpty) {
    state.setup.model = picked;
    state.notifyUi();
    return true;
  }
  await state.reloadHistory();
  // 显示的模型名跟服务端实际运行的一致：切完立刻重读一次（问题2）。
  await state.refreshModelLabel();
  return true;
}

/// 选模式（Agent 预设）：已有会话立即切（bridge 只允许空白会话切）；
/// 还没有会话就记成草稿（建会话时随 session-create 下发）。
Future<bool> pickSessionPreset(
  BuildContext context,
  ChatState state,
  DsColors colors,
) async {
  final sid = state.sessionId;
  final presets = await state.loadAgentPresets();
  if (presets == null || !context.mounted) return false;
  if (presets.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('当前桥没有可用的模式')),
    );
    return false;
  }
  final picked = await showPresetSheet(
    context,
    colors: colors,
    gateway: state.gateway,
    presets: presets,
    sessionId: sid,
    currentPresetId: state.currentAgentPresetId,
  );
  if (picked == null) return false;
  if (sid == null || sid.isEmpty) {
    state.setup.agentPresetId = picked.id;
    state.setup.agentPresetName = picked.name;
    state.notifyUi();
    return true;
  }
  try {
    await state.gateway.selectAgentPreset(sid, picked.id);
  } on RequestException catch (e) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          e.code == 'HTTP_409' ? '已锁定，仅空白会话可切换' : e.message,
        ),
      ),
    );
    return false;
  }
  await state.loadSessions();
  return true;
}
