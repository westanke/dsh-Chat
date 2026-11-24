/// 新会话的配置草稿（问题1：新建会话时模型 / 模式 / 权限都要能先选）。
///
/// 协议层没有「建会话时带模型 / 权限」的帧：bridge 的 `session-create` 只吃
/// `rootId / cwd / workspaceId / agentPreset / reuseBlank`（ws-sessions.ts:49-95），
/// 会话维度的模型与权限只有 `select-model` / `permission` 两帧，都要会话号。
/// 所以客户端走「先选 → 建会话 → 补应用」两步：草稿存在 [ChatSetupDraft]，
/// 会话建好后由 [applyChatSetup] 补发那两帧。
library;

import '../bridge/gateway.dart';
import '../bridge/models_view.dart';

/// 建会话前先选好的配置。
class ChatSetupDraft {
  /// 待应用的模型三元组（provider / model / reasoningEffort）。
  ModelSelection? model;

  /// 待应用的权限档位值（bridge 的 permission 档位 id）。
  String? permissionValue;

  /// 权限档位的展示名（＋面板行右侧显示）。
  String? permissionLabel;

  /// 待应用的模式（Agent 预设 id）。
  String? agentPresetId;

  /// 模式的展示名。
  String? agentPresetName;

  /// 待应用的计划模式开关（null = 没选过）。
  ///
  /// `/plan` 是命令帧（要会话号），所以新建会话时只能先存着，
  /// 建会话后由 [applyChatSetup] 补发一次 `/plan`。
  bool? plan;

  /// 是否还有没落地的配置。
  bool get isEmpty =>
      model == null &&
      permissionValue == null &&
      agentPresetId == null &&
      plan == null;

  /// 清空草稿（已经补应用过）。
  void clear() {
    model = null;
    permissionValue = null;
    permissionLabel = null;
    agentPresetId = null;
    agentPresetName = null;
    plan = null;
  }
}

/// 把草稿补应用到一个已经建好的会话。
///
/// 会话维度只有三帧能落配置：`select-model`（模型）、`permission`（权限档位）
/// 与 `command-execute`（`/plan`，计划模式）。
/// 模式（Agent 预设）**不在这里补**：它随 `session-create` 的 `agentPreset`
/// 字段下发（bridge ws-sessions.ts:49-95），建会话那一步已经带上了；再补一次
/// 反而会在非空白会话上撞 409 `AGENT_PRESET_LOCKED`。
///
/// 逐项独立失败：某一项挂了就报那项，不影响其余。
Future<void> applyChatSetup(
  GatewayClient gateway,
  String sessionId,
  ChatSetupDraft draft, {
  void Function(String message)? onError,
}) async {
  final model = draft.model;
  final permission = draft.permissionValue;
  final plan = draft.plan;
  draft.clear();
  if (model != null) {
    try {
      await gateway.selectModel(
        sessionId: sessionId,
        provider: model.provider,
        model: model.model,
        reasoningEffort: model.reasoningEffort,
      );
    } on RequestException catch (e) {
      onError?.call('模型切换失败：${e.message}');
    }
  }
  if (permission != null) {
    try {
      await gateway.setPermission(sessionId, permission);
    } on RequestException catch (e) {
      onError?.call('权限档位切换失败：${e.message}');
    }
  }
  if (plan != null) {
    // 计划模式是命令帧：与输入条上的开关同一对内核命令（/plan / /plan off）。
    try {
      final r = await gateway.executeCommand(
        sessionId: sessionId,
        line: plan ? '/plan' : '/plan off',
      );
      final result = r['result'];
      final kind = result is Map ? (result['kind'] ?? '') as String : '';
      if (kind == 'error') {
        final text = result is Map && result['text'] is String
            ? result['text'] as String
            : '命令执行失败';
        onError?.call('计划模式设置失败：$text');
      }
    } on RequestException catch (e) {
      onError?.call('计划模式设置失败：${e.message}');
    }
  }
}
