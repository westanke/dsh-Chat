// 会话列表的行模型。
//
// 列表只认行，不认消息：消息序列在不同折叠档位下派生出不同的行序列。
// 每行有一个稳定主键（key）——列表 diff、视口锚定、行级缓存都靠它。
//
// 结构参照 dsh-go（app/lib/ui/chat/chat_rows.dart），只借结构：
// 视觉、措辞、组件仍用本仓的 token 与既有 widget。

import 'package:flutter/foundation.dart';

import 'package:dshchat/bridge/models.dart';
import 'package:dshchat/design/app_settings.dart';
import 'package:dshchat/ui/chat_expand_state.dart';
import 'package:dshchat/ui/turn_changes.dart';
import 'package:dshchat/ui/work_steps.dart';

/// 会话列表的一行。由 [deriveRows] 从消息序列派生。
sealed class ChatRow {
  const ChatRow();

  /// 稳定主键：同一批消息在多次派生之间保持不变。
  String get key;

  /// 用作视口分界锚点的候选：内容不会再被合并 / 替换的行。
  bool get stable => false;

  /// 这行对应的消息在消息列表里的下标；不属于任何消息的行取 -1。
  int get index => -1;

  /// 这一行的外观能否缓存。
  ///
  /// 内容不来自行自身的行不能缓存：流式正文每次重建都不同，
  /// 缓存下来会把最新一段文字冻住。
  bool get cacheable => true;
}

/// 用户消息。
final class UserRow extends ChatRow {
  const UserRow(this.message, {required this.index});

  final ChatMessage message;
  @override
  final int index;

  @override
  String get key => message.seq >= 0
      ? 'u${message.seq}'
      : 'pu${identityHashCode(message)}';

  @override
  bool get stable => message.seq >= 0;
}

/// 助手正文。
final class AssistantRow extends ChatRow {
  const AssistantRow(this.message, {required this.index});

  final ChatMessage message;
  @override
  final int index;

  @override
  String get key => message.seq >= 0
      ? 'a${message.seq}'
      : 'pa${identityHashCode(message)}';

  @override
  bool get stable => message.seq >= 0;
}

/// 工具过程组（一组工具调用）。
final class ProcessRow extends ChatRow {
  const ProcessRow(this.message, {required this.index});

  final ChatMessage message;
  @override
  final int index;

  @override
  String get key => 'g${processGroupKeyOf(message)}';
}

/// 失败提示行（内核在轮出错时给的那条）。
final class ErrorRow extends ChatRow {
  const ErrorRow(this.message, {required this.index});

  final ChatMessage message;
  @override
  final int index;

  @override
  String get key => 'e${message.seq}';
}

/// 模型重试行（内核 `llm/retry`）：可展开的「已重试模型请求（1/5）· 1s」。
final class RetryRow extends ChatRow {
  const RetryRow(this.message, {required this.index});

  final ChatMessage message;
  @override
  final int index;

  @override
  String get key => 'rt${message.retryInfo?.retryId ?? message.seq}';
}

/// 交付文件卡。
final class FilesRow extends ChatRow {
  const FilesRow(this.message, {required this.index});

  final ChatMessage message;
  @override
  final int index;

  @override
  String get key => 'fl${message.seq}';
}

/// 本机命令卡。
final class CommandRow extends ChatRow {
  const CommandRow(this.message, {required this.index});

  final ChatMessage message;
  @override
  final int index;

  @override
  String get key => 'c${message.seq}';

  /// 命令卡的正文会在原消息对象上就地改写（执行结果回填），
  /// 缓存下来会把旧结果冻住。
  @override
  bool get cacheable => false;
}

/// 轮尾行：这一轮结束的摘要（用时 / 失败），点按可收起轮内过程组。
final class TurnEndRow extends ChatRow {
  const TurnEndRow(this.turn, {required this.hasProcess});

  final TurnRange turn;

  /// 这一轮里有没有过程组（没有就不出轮尾行）。
  final bool hasProcess;

  @override
  String get key => 'te${turn.start}';

  @override
  bool get stable => true;
}

/// 本轮改动卡：轮尾之后，「改动了 N 个文件」+ 逐文件增删行数。
final class ChangeCardRow extends ChatRow {
  const ChangeCardRow(this.changes, {required this.anchorSeq});

  final TurnChanges changes;

  /// 该轮首条消息的 seq（行的稳定主键）。
  final int anchorSeq;

  @override
  String get key => 'ch$anchorSeq';

  @override
  bool get stable => true;
}

/// 本轮生成文件卡：本轮新建 / 最终回复里引用的图片与文件。
final class ArtifactCardRow extends ChatRow {
  const ArtifactCardRow(this.files, {required this.anchorSeq});

  final List<ArtifactFile> files;
  final int anchorSeq;

  @override
  String get key => 'ar$anchorSeq';

  @override
  bool get stable => true;
}

/// 「加载更早消息」入口。
final class HistoryMoreRow extends ChatRow {
  const HistoryMoreRow();

  @override
  String get key => 'hm';
}

/// 「更早的历史被服务端裁剪掉」提示。
final class HistoryTruncatedRow extends ChatRow {
  const HistoryTruncatedRow();

  @override
  String get key => 'ht';
}

/// 流式工具组（工具帧实时缓冲合成，尚未落盘）。
final class StreamingProcessRow extends ChatRow {
  const StreamingProcessRow(this.group);

  final ChatMessage group;

  @override
  String get key => 'sg${processGroupKeyOf(group)}';

  @override
  bool get cacheable => false;
}

/// 流式正文。
final class StreamingTextRow extends ChatRow {
  const StreamingTextRow();

  @override
  String get key => 'st';

  @override
  bool get cacheable => false;
}

/// 「回答被截断」提示。
final class MaxTokensRow extends ChatRow {
  const MaxTokensRow();

  @override
  String get key => 'mt';
}

/// 链路错误提示。
final class LinkErrorRow extends ChatRow {
  const LinkErrorRow(this.message, {this.onRetry});

  final String message;

  /// 可重试错误（bridge error.retryable）才给「重试」。
  final VoidCallback? onRetry;

  @override
  String get key => 'le${message.hashCode}${onRetry != null ? 'r' : ''}';
}

/// 派生行序列所需的输入。
class ChatRowsInput {
  const ChatRowsInput({
    required this.messages,
    required this.folded,
    required this.streaming,
    required this.hasMoreHistory,
    required this.historyTruncated,
    required this.streamingProcess,
    required this.maxTokensNotice,
    required this.linkError,
    this.errorRetry,
  });

  final List<ChatMessage> messages;
  final FoldedReplies folded;
  final bool streaming;
  final bool hasMoreHistory;
  final bool historyTruncated;
  final ChatMessage? streamingProcess;
  final bool maxTokensNotice;
  final String? linkError;

  /// 错误条上的「重试」动作（仅 lastErrorRetryable 时传）。
  final VoidCallback? errorRetry;

  /// 派生结果的输入指纹：变了才重算。
  Object get signature => (
    messages.length,
    messages.isEmpty ? 0 : messages.last.seq,
    messages.isEmpty ? 0 : identityHashCode(messages.last),
    folded,
    streaming,
    hasMoreHistory,
    historyTruncated,
    streamingProcess == null ? 0 : identityHashCode(streamingProcess),
    maxTokensNotice,
    linkError,
    errorRetry != null,
  );
}

/// 把消息序列折成列表行。
///
/// 规则：
/// - 「收起后显示的回复」= [FoldedReplies.finalOnly] 且轮已完成时，
///   轮里只留最终回答（流式中永不过滤）；
/// - 工具过程组、用户消息、文件卡、命令卡、失败提示恒可见；
/// - 每轮最后补一条 [TurnEndRow]（轮内没有过程组时不出）。
List<ChatRow> deriveRows(ChatRowsInput input) {
  final messages = input.messages;
  final visible = Set<ChatMessage>.identity()
    ..addAll(visibleMessagesOf(messages, input.folded, input.streaming));
  final turns = turnsOf(messages);
  final rows = <ChatRow>[];

  if (input.hasMoreHistory) rows.add(const HistoryMoreRow());
  if (input.historyTruncated) rows.add(const HistoryTruncatedRow());

  for (var i = 0; i < messages.length; i++) {
    final message = messages[i];
    if (!visible.contains(message)) continue;
    rows.add(_rowFor(message, i));
    final turn = _turnEndingAt(turns, i);
    if (turn == null) continue;
    if (!_turnHasProcess(messages, turn)) continue;
    // 轮还在跑：不出轮尾行（问题 4：没执行完不能显示「已完成」）；
    // 改动/生成卡同样等轮结束，工具结果没到齐时计数会一路跳。
    if (turnIsRunning(messages, turn, input.streaming)) continue;
    rows.add(TurnEndRow(turn, hasProcess: true));
    final changes = turnChangesOf(messages, turn);
    if (changes != null && !changes.isEmpty) {
      rows.add(ChangeCardRow(changes, anchorSeq: changes.anchorSeq));
    }
    final artifacts = turnArtifactsOf(messages, turn);
    if (artifacts.isNotEmpty) {
      rows.add(
        ArtifactCardRow(
          artifacts,
          anchorSeq: changes?.anchorSeq ?? messages[turn.start].seq,
        ),
      );
    }
  }

  final streamingGroup = input.streamingProcess;
  if (streamingGroup != null) rows.add(StreamingProcessRow(streamingGroup));
  if (input.streaming) rows.add(const StreamingTextRow());
  if (input.maxTokensNotice) rows.add(const MaxTokensRow());
  final error = input.linkError;
  if (error != null) rows.add(LinkErrorRow(error, onRetry: input.errorRetry));

  return rows;
}

/// 一条消息对应哪一行。
ChatRow _rowFor(ChatMessage message, int index) {
  if (message.isUser) return UserRow(message, index: index);
  if (message.isProcess) return ProcessRow(message, index: index);
  if (message.isError) return ErrorRow(message, index: index);
  if (message.isRetry) return RetryRow(message, index: index);
  if (message.role == 'files') return FilesRow(message, index: index);
  if (message.role == 'command') return CommandRow(message, index: index);
  return AssistantRow(message, index: index);
}

/// 找以 [index] 结尾的轮。
TurnRange? _turnEndingAt(List<TurnRange> turns, int index) {
  for (final turn in turns) {
    if (turn.end - 1 == index) return turn;
  }
  return null;
}

/// 一轮里有没有过程组。
bool _turnHasProcess(List<ChatMessage> messages, TurnRange turn) {
  for (var i = turn.start + 1; i < turn.end; i++) {
    if (messages[i].isProcess) return true;
  }
  return false;
}

/// 这次派生是不是「前插了更早的历史」：消息变多，且最老的非负 seq 变小。
///
/// 前插时老行的 delegate 下标不变（不变量见 chat_list.dart 文件头），
/// 列表不需要校正锚点；但行缓存要整体清掉——缓存按行对象记，
/// 行数组头部多了一段后旧的按下标算出来的间距会错位。
bool didPrependHistory(List<ChatMessage> previous, List<ChatMessage> next) {
  if (previous.isEmpty || next.length <= previous.length) return false;
  return _oldestSeq(next) < _oldestSeq(previous);
}

int _oldestSeq(List<ChatMessage> messages) {
  var oldest = 1 << 30;
  for (final m in messages) {
    if (m.seq >= 0 && m.seq < oldest) oldest = m.seq;
  }
  return oldest;
}
