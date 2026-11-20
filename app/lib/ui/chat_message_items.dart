// ---------- 消息项（从 chat_page.dart 拆出，宪法 §7 控行数） ----------

library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../bridge/models.dart';
import '../bridge/platform.dart';
import '../design/app_settings.dart';
import '../design/tokens.dart';
import 'chat_expand_state.dart';
import 'chat_image.dart';
import 'chat_state.dart';
import 'chat_thinking.dart';
import 'md_view.dart';
import 'md_viewer.dart';
import 'message_actions.dart';
import 'process_group.dart';
import 'work_steps.dart';

class MessageItem extends StatelessWidget {
  const MessageItem({
    super.key,
    required this.message,
    required this.colors,
    required this.index,
    required this.state,
  });

  final ChatMessage message;
  final DsColors colors;
  final int index;
  final ChatState state;

  /// 下载器（chat_page build 时注入，见 imageFetcher）。
  static ImageFetcher? imageFetcher;

  /// 助手消息文本里的 image-handoff 占位（纯文本模型发图回路）。
  DsImageRef? get _handoff => handoffRefOf(message.text);

  /// ask_user_question 的 answerable：HITL 挂起表里还有同 callId 的提问
  /// （官方 AskQuestionRow 的 answerable 口径；不把整个 HitlState 塞进来）。
  bool _answerable(String callId) => state.hitl
      .sessionQuestions(state.sessionId)
      .any((q) => q.callId == callId);

  /// [index] 所在轮（不在任何轮里返回 null）。
  TurnRange? _turnOfIndex(int index) {
    for (final turn in turnsOf(state.messages)) {
      if (turn.contains(index)) return turn;
    }
    return null;
  }

  /// 运行中组标题的思考流兜底：组之前（同轮内）最近一条带 reasoning 的
  /// 助手消息的最后一段非空文本（官方取组内 thinking 项；我们的过程组
  /// 不携带 reasoning，由上层传）。
  String? _reasoningHint(TurnRange? turn, int index) {
    if (turn == null) return null;
    for (var i = index - 1; i > turn.start; i--) {
      final m = state.messages[i];
      if (m.role == 'assistant' && m.reasoning.trim().isNotEmpty) {
        return m.reasoning;
      }
    }
    return null;
  }

  /// 双击复制整条消息（对照 companion ChatMessageItems.kt 的
  /// combinedClickable onDoubleClick + ClipboardManager）。
  Future<void> _copyAll(BuildContext context) async {
    if (message.text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: message.text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制整条消息')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 工具调用过程组：折叠成聚合标题行（官方 Web 词表，tool_present.dart），
    // 点开展开明细；verbose 平铺逐条 DsToolRow，运行中轮的组 forceOpen。
    if (message.isProcess) {
      final detail = appSettings.workStepsDetail;
      if (detail.stepGrouping == WorkStepGrouping.none) {
        // verbose 完全展开：无组标题，逐条工具行（每条自带详情展开）。
        final calls = message.toolCalls;
        if (calls.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final call in calls)
              DsToolRow(
                call: call,
                colors: colors,
                allowDetail: true,
                answerable: _answerable,
              ),
          ],
        );
      }
      // 展开态托管在 ChatState（key=首个 callId，跨 reload 稳定）；
      // 运行中轮的组默认展开（官方 alwaysOpen），用户收起过则不再强推。
      final key = processGroupKeyOf(message);
      final turn = _turnOfIndex(index);
      final turnRunning = turn != null &&
          turnIsRunning(state.messages, turn, state.streaming);
      final forceOpen = turnRunning &&
          detail.foldCompletedTurns &&
          !state.isForceOpenDismissed(key);
      return DsProcessGroup(
        group: message,
        colors: colors,
        detail: detail,
        expanded: state.isGroupExpanded(key),
        forceOpen: forceOpen,
        onToggle: () => state.toggleProcessGroup(
          key,
          open: state.isGroupExpanded(key) || forceOpen,
        ),
        reasoningHint: _reasoningHint(turn, index),
        answerable: _answerable,
      );
    }
    // 文件卡（第四轮反馈 6）：present 工具交付的文件列表。
    if (message.role == 'files') {
      return DeliverablesCard(
        files: message.files,
        colors: colors,
        gateway: state.gateway,
      );
    }
    // 命令卡（第六轮反馈 m03878）：斜杠命令执行的本地回执——
    /// 首行命令行（terminal 图标），次行 ✓/✗ 结果。仅本机内存，不入历史。
    if (message.role == 'command') {
      final lines = message.text.split('\n');
      final failed = message.text.contains('\n✗');
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.bgLayer1,
          borderRadius: BorderRadius.circular(DsSpacing.codeBlockRadius),
          border: Border.all(color: colors.inputBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.terminal,
              size: 15,
              color: failed ? colors.danger : colors.chipSelectedFg,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lines.first,
                    style: DsTypography.small.copyWith(
                      color: colors.labelPrimary,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (lines.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        lines.skip(1).join('\n'),
                        style: DsTypography.small.copyWith(
                          color: failed ? colors.danger : colors.labelTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    // 一轮 turn 失败（模型限流 / 额度 / 网关报错）：官方是红色错误提示，
    // 这里同样用 danger 色块呈现，而不是静默什么都不显示。
    if (message.isError) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(DsSpacing.codeBlockRadius),
        ),
        child: Text(
          message.text,
          style: DsTypography.small.copyWith(color: colors.danger),
        ),
      );
    }
    // 双击复制：包在气泡/正文外，不挂 onLongPress（否则选词手柄出不来）。
    // 用户气泡宽度随可见页面宽度缩放（issue #1：固定 280dp 不随屏宽走）。
    // LayoutBuilder 取父级可用宽 × userBubbleMaxFraction，自动涵盖列表
    // padding 与平板分栏；360dp 屏 ≈ 279dp 与官方基准一致。
    final bubble = message.role == 'user'
        ? LayoutBuilder(
            builder: (context, box) {
              final page = MediaQuery.sizeOf(context).width;
              final avail = box.maxWidth.isFinite ? box.maxWidth : page;
              return Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(left: DsSpacing.hMargin),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              constraints: BoxConstraints(
                maxWidth: avail * DsSpacing.userBubbleMaxFraction,
              ),
              decoration: BoxDecoration(
                color: colors.userBubble,
                borderRadius: BorderRadius.circular(DsSpacing.bubbleRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 历史图片（attachment 引用；真机反馈 2026-11-04 第 1 项）。
                  for (final ref in imageRefsOf(message.images))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DsChatImage(
                        ref: ref,
                        colors: colors,
                        fetcher: imageFetcher!,
                      ),
                    ),
                  if (message.text.isNotEmpty)
                    Text(
                      message.text,
                      style: DsTypography.base.copyWith(
                        color: colors.userBubbleText,
                        height: 24 / 16,
                      ),
                    ),
                ],
              ),
            ),
           ); // Align（气泡容器，return 结束）
           },
         )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (message.reasoning.isNotEmpty)
                ThinkingRow(
                  text: message.reasoning,
                  colors: colors,
                  // concise 档折叠态只留标题，不显示正文预览。
                  showPreview:
                      appSettings.workStepsDetail.settledReasoningPreview,
                ),
              // 纯文本模型的图片交接（反馈第 8 条手机端显示回路）：
              // 文本里的 [Image: source: .../<sha256>.<ext>] 占位换成取回的图。
              if (_handoff != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DsChatImage(
                    ref: _handoff!,
                    colors: colors,
                    fetcher: imageFetcher!,
                  ),
                ),
              DsMarkdownView(text: message.text, colors: colors),
              DsMessageActions(
                colors: colors,
                text: message.text,
                sentAt: message.startedAt,
                onRegenerate: () => state.regenerateAt(index),
              ),
            ],
          );
    return GestureDetector(
      onDoubleTap: () => _copyAll(context),
      child: bubble,
    );
  }
}

class StreamingItem extends StatelessWidget {
  const StreamingItem({super.key, required this.state, required this.colors});

  final ChatState state;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.streamReasoning.isNotEmpty)
          ThinkingRow(
            text: state.streamReasoning,
            colors: colors,
            streaming: true,
            answerStarted: state.streamText.isNotEmpty,
          ),
        DsMarkdownView(
          text: state.streamText,
          colors: colors,
          streaming: true,
        ),
      ],
    );
  }
}

// ---------- 文件卡（第四轮反馈 6：deliverables/presented） ----------

/// 交付文件卡：图标 + 文件名 + 描述（第四轮反馈 6 + m03452 改进）。
/// 点击：.md/.markdown → 全屏 Markdown 渲染页（resolve + readContent 取字节）；
/// 其他类型 → 系统打开（openFile，FileProvider + ACTION_VIEW）；
/// 都失败回退系统分享。md 渲染页需要 gateway（长文档滚动可读）。
class DeliverablesCard extends StatelessWidget {
  const DeliverablesCard({
    super.key,
    required this.files,
    required this.colors,
    required this.gateway,
  });

  final List<DeliverableFile> files;
  final DsColors colors;

  /// 当前会话的 gateway（resolve/readContent/openFile 都要走 REST）。
  final GatewayClient gateway;

  bool _isMarkdown(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown');
  }

  void _open(BuildContext context, DeliverableFile f) {
    if (_isMarkdown(f.path)) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => MdViewerPage(
            gateway: gateway,
            absolutePath: f.path,
            title: f.name,
            colors: colors,
          ),
        ),
      );
      return;
    }
    _openWithSystem(context, f);
  }

  /// 非 md：先 resolve 确认可读，取字节交给系统「打开方式」；
  /// 失败回退系统分享（体验兜底，不留死交互）。
  Future<void> _openWithSystem(BuildContext context, DeliverableFile f) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final resolved =
          await gatewayResolvePath(gateway, f.path);
      final bytes =
          await gatewayReadFileBytes(gateway, resolved.rootId, resolved.path);
      final ok = await DshPlatform.openFile(
        name: f.name,
        bytes: bytes,
        mime: resolved.contentType,
      );
      if (!messenger.mounted) return;
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('没有可打开此文件的应用，改为分享')),
        );
        await DshPlatform.share(f.path);
      }
    } on RequestException {
      _fallbackShare(messenger, '文件读取失败，改为分享');
    } on Exception {
      _fallbackShare(messenger, '打开失败，改为分享');
    }
  }

  Future<void> _fallbackShare(
    ScaffoldMessengerState messenger,
    String tip,
  ) async {
    // 注意：这里分享的是路径文本（老行为），不是文件字节——字节分享需要
    // 临时文件 + FileProvider，作为纯兜底不值得引入。
    final ok = await DshPlatform.share(
      files.where((f) => f.path.isNotEmpty).map((f) => f.path).join('\n'),
    );
    if (!messenger.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(tip)));
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('分享暂不可用')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colors.bgLayer1,
        borderRadius: BorderRadius.circular(DsSpacing.bubbleRadius),
        border: Border.all(color: colors.borderL2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final f in files)
            InkWell(
              onTap: () => _open(context, f),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.insert_drive_file_outlined,
                      size: 22,
                      color: colors.brand,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DsTypography.base.copyWith(
                              color: colors.labelPrimary,
                            ),
                          ),
                          if (f.description != null && f.description!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                f.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: DsTypography.small.copyWith(
                                  color: colors.labelTertiary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.ios_share,  // md 卡片也用它（点开即预览）
                      size: 16,
                      color: colors.labelTertiary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
