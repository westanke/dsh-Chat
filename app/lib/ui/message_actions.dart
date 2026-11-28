/// 助手消息底部操作条 —— 官方 App 实测复刻。
///
/// 官方（ref/md-shot-3-code.png，1080x2400 @3.0）：
///   图标垂直中心 y≈1915，图标 30px ≈ 10dp 视觉尺寸（线框风格，tertiary 灰）；
///   左起 4 个：复制 / 点赞 / 朗读 / 分享，间距约 20dp；
///   最右侧单独一个「重新生成」刷新图标（x≈1001，右对齐）。
/// 点踩图标按真机反馈（2026-11-04）移除。
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../bridge/platform.dart';
import '../design/tokens.dart';
import 'quote_preview.dart';

/// 消息操作条：复制 / 引用 / 喜欢 / 朗读 / 分享 —— 右侧重新生成。
///
/// 「引用」只在调用方传了 [onQuote] 时出现（助手与用户消息都复用本组件，
/// 来源由 [quoteAuthor] 指定）。
class DsMessageActions extends StatefulWidget {
  const DsMessageActions({
    super.key,
    required this.colors,
    required this.text,
    this.sentAt,
    this.messageSeq = -1,
    this.quoteAuthor = QuoteAuthor.assistant,
    this.messageId,
    this.onRegenerate,
    this.onFork,
    this.onQuote,
  });

  final DsColors colors;
  final String text;

  /// 该消息的服务端序号：构造 [QuoteTarget] 用。流式消息没有序号时保持 -1；
  /// 调用方一般只在 seq>=0 时传 [onQuote]。
  final int messageSeq;

  /// 该消息的发出者（用户消息传 [QuoteAuthor.you]）。
  final QuoteAuthor quoteAuthor;

  /// 该消息的服务端 id（协议里有就带上，可空）。
  final String? messageId;

  /// 「引用」入口：null 不渲染该按钮；非 null 时点击回传
  /// 「本条消息的 seq / author / text」构成的 [QuoteTarget]。
  final ValueChanged<QuoteTarget>? onQuote;

  /// 消息发送时间（epochMs，第四轮反馈 7）：分享文本尾部附加，
  /// 让分享出去的内容带时间戳。null 不加。
  final int? sentAt;
  final VoidCallback? onRegenerate;

  /// 「从此消息分叉」：仅已落库消息（seq>=0）传入；流式消息没有
  /// 服务端序号，构造层传 null，这一项就不出现。
  final VoidCallback? onFork;

  @override
  State<DsMessageActions> createState() => _DsMessageActionsState();
}

class _DsMessageActionsState extends State<DsMessageActions> {
  bool _liked = false;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// 朗读：调系统 TTS（dsh/platform 通道，真机反馈 2026-11-04）。
  /// 平台未实现（iOS 暂缓）或 TTS 失败时明确提示，不留死交互。
  Future<void> _speak(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context); // 组合期取，避免 async gap
    final ok = await DshPlatform.speak(widget.text);
    if (!messenger.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? '正在朗读' : '朗读暂不可用')),
    );
  }

  /// 分享：调系统分享面板（Android Intent.createChooser）。
  /// 文本尾部附发送时间（第四轮反馈 7）：「—— 发送于 2026-11-05 10:06」。
  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final at = widget.sentAt;
    final body = at == null
        ? widget.text
        : '${widget.text}\n\n—— 发送于 ${formatSentTime(at)}';
    final ok = await DshPlatform.share(body);
    if (!messenger.mounted) return;
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('分享暂不可用')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    // 出血 8：图标格 36 内图标 20，左右各 8 的白；把整条左移 8，让第一个图标
    // 的墨迹贴正文左缘（dsh-go message_actions 的 Bleed(horizontal: 8)）。
    return Transform.translate(
      offset: const Offset(-8, 0),
      child: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          _ActionIcon(
            icon: _copied ? Icons.check : Icons.content_copy_outlined,
            color: c.labelTertiary,
            tooltip: _copied ? '已复制' : '复制',
            onTap: _copy,
          ),
          if (widget.onQuote != null && _hasVisibleText(widget.text))
            _ActionIcon(
              icon: Icons.format_quote_outlined,
              color: c.labelTertiary,
              tooltip: '引用',
              onTap: () => widget.onQuote!(
                QuoteTarget(
                  messageSeq: widget.messageSeq,
                  author: widget.quoteAuthor,
                  text: widget.text,
                  messageId: widget.messageId,
                ),
              ),
            ),
          _ActionIcon(
            icon: _liked ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
            color: _liked ? c.brand : c.labelTertiary,
            tooltip: '喜欢',
            onTap: () => setState(() => _liked = !_liked),
          ),
          _ActionIcon(
            icon: Icons.volume_up_outlined,
            color: c.labelTertiary,
            tooltip: '朗读',
            onTap: () => _speak(context),
          ),
          _ActionIcon(
            icon: Icons.share_outlined,
            color: c.labelTertiary,
            tooltip: '分享',
            onTap: () => _share(context),
          ),
          if (widget.onFork != null)
            _ActionIcon(
              icon: Icons.call_split,
              color: c.labelTertiary,
              tooltip: '从此消息分叉',
              onTap: widget.onFork,
            ),
          const Spacer(),
          _ActionIcon(
            icon: Icons.refresh,
            color: c.labelTertiary,
            tooltip: '重新生成',
            onTap: widget.onRegenerate,
          ),
        ],
      ),
      ),
    );
  }
}

/// 发送时间格式化（第四轮反馈 7，无 intl 依赖）：
/// epochMs → 'yyyy-MM-dd HH:mm'（本地时区）。
String formatSentTime(int epochMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd $hh:$mi';
}

/// 有可展示的正文：去掉空白与零宽字符后仍有内容。
///
/// 历史里存在只带零宽字符的助手消息（工具轮的空正文），`trim()` 不认
/// ZWSP，会让「引用」入口出现在一条看起来没有文字的消息上。
bool _hasVisibleText(String raw) =>
    raw.replaceAll(_invisible, '').isNotEmpty;

final RegExp _invisible = RegExp(r'[\s\u200B\u200C\u200D\u2060\uFE0E\uFE0F\uFEFF]');

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // dsh-go message_actions.dart：IconButton 36×36、图标 20、点击格 shrinkWrap，
    // 相邻按钮之间留 actionIconGap（8）。整条再向左出血 8，让第一个图标贴正文左缘。
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 36,
        child: InkResponse(
          onTap: onTap,
          radius: 20,
          child: Center(child: Icon(icon, size: 20, color: color)),
        ),
      ),
    );
  }
}
