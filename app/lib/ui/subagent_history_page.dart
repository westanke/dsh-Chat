/// 子会话（团队成员）历史查看页 —— 第四轮反馈 3。
/// REST 只读窄口 GET /chat/sessions/{leadId}/subagents/{subagentId}/messages
/// （openapi.yaml:992-1050）：Lead 可见 + 内核投影背书成员关系，只读不可写。
/// 拆出原因：宪法 §7 单文件 ≤500 行（projection_sheets.dart 已近线）。
library;

import 'package:flutter/material.dart';

import '../bridge/gateway.dart';
import '../bridge/models.dart';
import '../bridge/projections.dart';
import '../design/tokens.dart';
import 'md_view.dart';

// ---------- 子会话历史查看页（第四轮反馈 3） ----------

/// 团队成员（subagent）会话的只读历史页：REST 窄口拉取（subagentHistory），
/// 装配 HistoryPage 后复用消息渲染。只读——协议明确 subagent 会话不可写
/// （openapi.yaml:1010-1016，写会模糊 Lead/成员指挥关系），无输入条。
class SubagentHistoryPage extends StatefulWidget {
  const SubagentHistoryPage({
    super.key,
    required this.gateway,
    required this.leadSessionId,
    required this.subagent,
    required this.colors,
  });

  final GatewayClient gateway;
  final String leadSessionId;
  final SubagentRow subagent;
  final DsColors colors;

  @override
  State<SubagentHistoryPage> createState() => _SubagentHistoryPageState();
}

class _SubagentHistoryPageState extends State<SubagentHistoryPage> {
  HistoryPage? _page;
  String? _error;
  bool _loading = true;
  bool _loadingOlder = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.gateway.subagentHistory(
        widget.leadSessionId,
        widget.subagent.id,
        maxMessages: 80,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } on RequestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
        _loading = false;
      });
    }
  }

  /// 翻页：以当前最旧一条事件的 seq 为 beforeSeq 续拉。
  Future<void> _loadOlder() async {
    final page = _page;
    if (page == null || _loadingOlder) return;
    final oldest = page.items
        .where((m) => m.seq >= 0)
        .map((m) => m.seq)
        .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    if (oldest == null) return;
    setState(() => _loadingOlder = true);
    try {
      final older = await widget.gateway.subagentHistory(
        widget.leadSessionId,
        widget.subagent.id,
        maxMessages: 80,
        beforeSeq: oldest,
      );
      if (!mounted) return;
      setState(() {
        _page = HistoryPage(
          items: [...older.items, ...page.items],
          hasMore: older.hasMore,
          rawEvents: [...older.rawEvents, ...page.rawEvents],
        );
        _loadingOlder = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() => _loadingOlder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Scaffold(
      backgroundColor: c.bgBase,
      appBar: AppBar(
        backgroundColor: c.bgBase,
        elevation: 0,
        title: Text(
          widget.subagent.label.isEmpty
              ? '子会话 ${widget.subagent.id.substring(0, 8)}'
              : widget.subagent.label,
          style: DsTypography.pageTitle.copyWith(color: c.labelPrimary),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(DsSpacing.screenPad),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: DsTypography.small.copyWith(
                              color: c.danger,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(onPressed: _load, child: const Text('重试')),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.symmetric(
                      horizontal: DsSpacing.hMargin,
                      vertical: DsSpacing.screenPad,
                    ),
                    itemCount: (_page!.hasMore ? 1 : 0) + _page!.items.length,
                    itemBuilder: (context, i) {
                      if (_page!.hasMore && i == 0) {
                        return Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.only(bottom: DsSpacing.blockGap),
                            child: _loadingOlder
                                ? const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : TextButton.icon(
                                    onPressed: _loadOlder,
                                    icon: const Icon(Icons.expand_less,
                                        size: 18),
                                    label: const Text('加载更早消息'),
                                  ),
                          ),
                        );
                      }
                      final idx = i - (_page!.hasMore ? 1 : 0);
                      return _SubagentMessageItem(
                        message: _page!.items[idx],
                        colors: c,
                      );
                    },
                  ),
      ),
    );
  }
}

/// 子会话历史的轻量消息渲染（只读）：正文 / 过程组短语 / 错误 / 文件卡。
/// 不复用 _MessageItem——那是 chat_page 库的私有 part，且挂着
/// regenerate/复制整条等交互回路；此处只读展示足够。
class _SubagentMessageItem extends StatelessWidget {
  const _SubagentMessageItem({required this.message, required this.colors});

  final ChatMessage message;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final m = message;
    if (m.isProcess) {
      return Padding(
        padding: const EdgeInsets.only(top: DsSpacing.blockGap),
        child: Text(
          m.phraseText,
          style: DsTypography.small.copyWith(color: c.labelTertiary),
        ),
      );
    }
    if (m.isError) {
      return Padding(
        padding: const EdgeInsets.only(top: DsSpacing.blockGap),
        child: Text(
          m.text,
          style: DsTypography.small.copyWith(color: c.danger),
        ),
      );
    }
    if (m.role == 'files') {
      return Padding(
        padding: const EdgeInsets.only(top: DsSpacing.blockGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final f in m.files)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(Icons.insert_drive_file_outlined,
                        size: 18, color: c.brand),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f.path,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DsTypography.small.copyWith(
                          color: c.labelSecondary,
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
    // user / assistant 正文（含 reasoning 折叠省略——只读页从简）。
    return Padding(
      padding: const EdgeInsets.only(top: DsSpacing.blockGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m.isUser)
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: const BoxConstraints(maxWidth: 280),
                decoration: BoxDecoration(
                  color: c.userBubble,
                  borderRadius:
                      BorderRadius.circular(DsSpacing.bubbleRadius),
                ),
                child: Text(
                  m.text,
                  style: DsTypography.base.copyWith(
                    color: c.userBubbleText,
                    height: 24 / 16,
                  ),
                ),
              ),
            )
          else ...[
            DsMarkdownView(text: m.text, colors: c),
          ],
        ],
      ),
    );
  }
}
