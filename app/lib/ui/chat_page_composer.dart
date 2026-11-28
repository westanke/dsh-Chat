/// 主聊天页的输入条装配（从 chat_page.dart 拆出，宪法 §7 单文件 ≤500 行）。
///
/// 只做一件事：把 ChatState 的当前状态接到 [Composer] 的参数上。
/// 「+」面板的四行（模型 / 模式 / 权限 / 计划模式）在新建会话时也能点：
/// 没有会话时选中的先存进 [ChatSetupDraft]，建会话后由
/// `applyChatSetup` 补应用（见 chat_setup_draft.dart）。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../design/tokens.dart';
import 'chat_setup.dart';
import 'chat_state.dart';
import 'composer.dart';
import 'quote_preview.dart';

/// 装出输入条。
///
/// [activity] / [todoDock] 只用来算上方间距（有 dock 时收到 6，否则 16）。
Widget buildChatComposer({
  required BuildContext context,
  required ChatState state,
  required DsColors colors,
  required GlobalKey<ComposerState> composerKey,
  required Object? activity,
  required Object? todoDock,
  required ValueChanged<String> onAppCommand,
  required VoidCallback onPickModel,
}) {
  final composer = Composer(
    key: composerKey,
    colors: colors,
    // 上方已有活动条/任务条时，间距收到 6（dsh-go dock 与输入条之间 6），
    // 否则保留 16 的正文间隔。
    topGap: (activity != null || todoDock != null)
        ? DsSpacing.dockStackGap
        : DsSpacing.blockGap,
    enabled: state.connectionState == GatewayState.ready,
    onSend: (text) {
      final quote = state.quote;
      if (quote == null) {
        state.send(text);
        return;
      }
      state.clearQuote();
      state.send(composeQuotedMessage(quote, text));
    },
    // 带图发送不拼引用：图片和引用同发没有产品定义，直接清掉避免残留。
    onSendWithImages: (text, images) {
      state.clearQuote();
      state.sendWithImages(text, images);
    },
    onCancel: state.cancelTurn,
    onCommand: state.runCommand,
    streaming: state.streaming,
    sessionId: state.sessionId,
    gateway: state.gateway,
    currentPermission: state.currentPermission,
    // @ 面板「对话」分组用抽屉同一份会话列表（工单 3）。
    sessions: state.sessions,
    // 单题提问挂着时，输入条文字直接作为答案（hint 同步切换）。
    answering: state.singleOpenQuestion != null,
    // 斜杠面板的客户端功能（/new /model /export /features）。
    onAppCommand: onAppCommand,
    // 输入条上的模型 chip：显示服务端 models 帧的 current.model。
    onPickModel: onPickModel,
    modelLabel: state.modelLabel,
    // 「+」面板：模式（Agent 预设）行。
    presetLabel: state.currentAgentPresetName ?? state.setup.agentPresetName,
    onPickPreset: () => pickSessionPreset(context, state, colors),
    // 「+」面板：没有会话时选好的权限档位先存草稿，建会话后补应用。
    pendingPermissionLabel: state.setup.permissionLabel,
    onPendingPermission: (option) {
      state.setup.permissionValue = option.value;
      state.setup.permissionLabel = option.label;
      state.notifyUi();
    },
    // 「+」面板：没有会话时选好的计划模式先存草稿，建会话后补发
    // /plan（命令帧要会话号）。
    pendingPlan: state.setup.plan,
    onPendingPlan: (on) {
      state.setup.plan = on;
      state.notifyUi();
    },
  );

  final quote = state.quote;
  if (quote == null) return composer;
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          DsSpacing.screenPad,
          DsSpacing.blockGap,
          DsSpacing.screenPad,
          0,
        ),
        child: QuotePreview(
          quote: quote,
          colors: colors,
          onClear: state.clearQuote,
        ),
      ),
      composer,
    ],
  );
}
