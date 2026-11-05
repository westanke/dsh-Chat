part of 'chat_page.dart';

// ---------- 消息项（从 chat_page.dart 拆出，宪法 §7 控行数） ----------

class _MessageItem extends StatelessWidget {
  const _MessageItem({
    required this.message,
    required this.colors,
    required this.index,
    required this.state,
  });

  final ChatMessage message;
  final DsColors colors;
  final int index;
  final ChatState state;

  /// 下载器（chat_page build 时注入，见 _imageFetcher）。
  static ImageFetcher? _imageFetcher;

  /// 助手消息文本里的 image-handoff 占位（纯文本模型发图回路）。
  DsImageRef? get _handoff => handoffRefOf(message.text);

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
    // 工具调用过程组：折叠成一行，点开展开明细。
    if (message.isProcess) {
      return DsProcessGroup(group: message, colors: colors);
    }
    // 文件卡（第四轮反馈 6）：present 工具交付的文件列表。
    if (message.role == 'files') {
      return _DeliverablesCard(
        files: message.files,
        colors: colors,
        gateway: state.gateway,
      );
    }
    // 一轮 turn 失败（模型限流 / 额度 / 网关报错）：官方是红色错误提示，
    // 这里同样用 danger 色块呈现，而不是静默什么都不显示。
    if (message.isError) {
      return Container(
        margin: const EdgeInsets.only(top: DsSpacing.blockGap),
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
    final bubble = message.role == 'user'
        ? Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(
                top: DsSpacing.blockGap,
                left: DsSpacing.hMargin,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              constraints: const BoxConstraints(maxWidth: 280),
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
                        fetcher: _imageFetcher!,
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
          )
        : Padding(
            padding: const EdgeInsets.only(top: DsSpacing.blockGap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (message.reasoning.isNotEmpty)
                  _ThinkBlock(text: message.reasoning, colors: colors),
                // 纯文本模型的图片交接（反馈第 8 条手机端显示回路）：
                // 文本里的 [Image: source: .../<sha256>.<ext>] 占位换成取回的图。
                if (_handoff != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DsChatImage(
                      ref: _handoff!,
                      colors: colors,
                      fetcher: _imageFetcher!,
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
            ),
          );
    return GestureDetector(
      onDoubleTap: () => _copyAll(context),
      child: bubble,
    );
  }
}

class _StreamingItem extends StatelessWidget {
  const _StreamingItem({required this.state, required this.colors});

  final ChatState state;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: DsSpacing.blockGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.streamReasoning.isNotEmpty)
            _ThinkBlock(
              text: state.streamReasoning,
              colors: colors,
              streaming: true,
            ),
          DsMarkdownView(
            text: state.streamText,
            colors: colors,
            streaming: true,
          ),
        ],
      ),
    );
  }
}

/// 思考流：官方「已深度思考」可折叠小字块。
/// [streaming] 为 true 时默认展开并显示「深度思考中…」（真机反馈第五轮
/// m03759：有思考时流式展示思考过程，而非折叠藏起来）；历史消息保持折叠。
class _ThinkBlock extends StatefulWidget {
  const _ThinkBlock({required this.text, required this.colors, this.streaming = false});

  final String text;
  final DsColors colors;
  final bool streaming;

  @override
  State<_ThinkBlock> createState() => _ThinkBlockState();
}

class _ThinkBlockState extends State<_ThinkBlock> {
  late bool _expanded = widget.streaming;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.thinkHMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.explore_outlined,
                    size: 14,
                    color: c.labelSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _expanded
                        ? '收起深度思考'
                        : widget.streaming
                            ? '深度思考中…'
                            : '已深度思考',
                    style: DsTypography.smallStrong.copyWith(
                      color: c.labelSecondary,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: c.labelSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(left: DsSpacing.thinkHMargin),
              child: DsMarkdownView(text: widget.text, colors: c, small: true),
            ),
        ],
      ),
    );
  }
}

// ---------- 文件卡（第四轮反馈 6：deliverables/presented） ----------

/// 交付文件卡：图标 + 文件名 + 描述（第四轮反馈 6 + m03452 改进）。
/// 点击：.md/.markdown → 全屏 Markdown 渲染页（resolve + readContent 取字节）；
/// 其他类型 → 系统打开（openFile，FileProvider + ACTION_VIEW）；
/// 都失败回退系统分享。md 渲染页需要 gateway（长文档滚动可读）。
class _DeliverablesCard extends StatelessWidget {
  const _DeliverablesCard({
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
      margin: const EdgeInsets.only(top: DsSpacing.blockGap),
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
