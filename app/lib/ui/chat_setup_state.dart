/// ChatState 的「会话配置」状态与动作（问题1：新建会话时模型 / 模式 / 权限可先选）。
///
/// 放在独立 mixin 而不是 chat_state.dart 里：chat_state.dart 已超单文件行数预算
/// （宪法 §7），且这样不用让 chat_state.dart 反向依赖 UI 层文件。
///
/// 协议事实：bridge 的 `session-create` 帧只吃 `rootId / cwd / workspaceId /
/// agentPreset / reuseBlank`（ws-sessions.ts:49-95）；会话维度的模型与权限只有
/// `select-model` / `permission` 两帧，都要求会话号。所以新会话的流程是
/// 「先选 → 建会话 → 补应用」。
library;

import 'package:flutter/foundation.dart';

import '../bridge/gateway.dart';
import '../bridge/models.dart';
import '../bridge/models_view.dart';
import 'chat_setup_draft.dart';

/// 配置草稿 + 模型文案（输入条模型 chip 显示什么）。
mixin ChatSetupState on ChangeNotifier {
  /// ChatState 已有的连接（由 ChatState 自己提供）。
  GatewayClient get gateway;

  /// ChatState 已有的当前会话号（由 ChatState 自己提供）。
  String? get sessionId;

  /// ChatState 已有的会话清单（由 ChatState 自己提供）。
  List<DshSession> get sessions;

  /// ChatState 已有的错误位（由 ChatState 自己提供）。
  String? get lastError;
  set lastError(String? value);

  /// 建会话前先选好的配置（模型 / 权限 / 模式）。
  final ChatSetupDraft setup = ChatSetupDraft();

  /// 输入条模型 chip 显示的模型名（会话维度；服务端 models 帧的 current.model）。
  ///
  /// 以前 chip 自己拉一次 models 帧并按会话号短路（`_loadedFor == sid`），
  /// 同会话内切完模型界面永远不更新（问题2）。现在文案由状态统一持有，
  /// 切完模型立刻重读一次 —— 显示的与实际运行的是同一个模型。
  String? modelLabel;

  /// 模式（Agent 预设）id → 名称缓存，给＋面板行显示用。
  final Map<String, String> agentPresetNames = {};

  /// 重读当前会话的模型名（服务端真源）。
  Future<void> refreshModelLabel() async {
    final sid = sessionId;
    if (sid == null || sid.isEmpty) {
      if (modelLabel != null) {
        modelLabel = null;
        notifyListeners();
      }
      return;
    }
    try {
      final models = SessionModels.parse(await gateway.sessionModels(sid));
      if (sid != sessionId) return;
      final name = models.current.model;
      if (modelLabel != name) {
        modelLabel = name.isEmpty ? null : name;
        notifyListeners();
      }
    } catch (_) {
      // 老桥没有 models 帧：留空（chip 不显示），别拿假名字占位。
    }
  }

  /// 当前会话的模式（Agent 预设）id。
  String? get currentAgentPresetId {
    final sid = sessionId;
    if (sid == null || sid.isEmpty) return null;
    for (final s in sessions) {
      if (s.id == sid) return s.agentPreset;
    }
    return null;
  }

  /// 当前会话的模式名（缓存里没有就退回 id）。
  String? get currentAgentPresetName {
    final id = currentAgentPresetId;
    if (id == null || id.isEmpty) return null;
    return agentPresetNames[id] ?? id;
  }

  /// 拉一次模式（Agent 预设）清单，并把 id → 名称缓存下来给面板显示。
  Future<List<GatewayAgentPreset>?> loadAgentPresets() async {
    try {
      final list = await gateway.agentPresets();
      for (final p in list) {
        agentPresetNames[p.id] = p.name;
      }
      notifyListeners();
      return list;
    } on RequestException catch (e) {
      lastError = '模式清单获取失败：${e.message}';
      notifyListeners();
      return null;
    }
  }

  /// 建会话成功后把「先选好的配置」补应用到这个会话（问题1）。
  ///
  /// 协议层没有「建会话时带模型 / 权限」的帧：会话维度的模型与权限只有
  /// `select-model` / `permission` 两帧，都要会话号。所以流程是「先选 →
  /// 建会话 → 补应用」（见 chat_setup_draft.dart）。
  Future<void> applySetupTo(String sid) async {
    if (setup.isEmpty) return;
    await applyChatSetup(
      gateway,
      sid,
      setup,
      onError: (message) {
        lastError = message;
        notifyListeners();
      },
    );
    await refreshModelLabel();
  }
}
