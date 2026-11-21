/// 会话待发送队列（bridge `mobile-queue-v1`）的模型与能力位。
///
/// 协议事实来源：dsh-remote-bridge `22a5223`（IKX1ZM）与客户端对接单
/// `westanke/dsh-Chat#IKX2AE`：
/// - 读 `session-queues` / 推送 `queue-item-updated`，都回整份 `queue`；
/// - 写 `queue-update{inboxId, action:remove|steer|edit, text?}`；
/// - 首屏 `history` 已带 `queue`，打开会话不必先发读帧；
/// - 身份一律用 `inboxId`（同文本可排两条）。
library;

/// 能力位：没有它时整块队列 UI 隐藏，也不发帧（老桥回 UNKNOWN_TYPE）。
const String queueCapability = 'mobile-queue-v1';

/// 一条待发送的输入（内核 inbox 项）。
class QueueEntry {
  const QueueEntry({
    required this.inboxId,
    required this.requestId,
    required this.slot,
    required this.mode,
    required this.text,
    required this.resendable,
    required this.sourceKind,
  });

  final String inboxId;

  /// 与 [inboxId] 同值；保留字段便于对照桥/内核两套命名。
  final String requestId;

  /// `next-step`（下一步插话）或 `next-turn`（本轮结束后发送）。
  final String slot;

  /// `steer` 或 `queue`（与 slot 一一对应，桥原样给）。
  final String mode;

  final String text;

  /// false = 带图/附件，不能「改完重发」，只能撤回/改插话。
  final bool resendable;

  /// 缺省 'user'（外部来源可能是分享/自动化）。
  final String sourceKind;

  bool get isNextStep => slot == 'next-step';

  /// 是否还有「编辑后重发」的意义（带图项没有原文可改）。
  bool get canEdit => resendable;

  static QueueEntry? from(Object? json) {
    if (json is! Map) return null;
    final inboxId = json['inboxId'];
    if (inboxId is! String || inboxId.isEmpty) return null;
    final requestId = json['requestId'];
    final slot = json['slot'];
    final text = json['text'];
    return QueueEntry(
      inboxId: inboxId,
      requestId: requestId is String && requestId.isNotEmpty
          ? requestId
          : inboxId,
      slot: slot is String ? slot : 'next-turn',
      mode: json['mode'] is String ? json['mode'] as String : 'queue',
      text: text is String ? text : '',
      resendable: json['resendable'] != false,
      sourceKind: json['sourceKind'] is String
          ? json['sourceKind'] as String
          : 'user',
    );
  }

  /// 队列快照解析：形状不对或缺失回空表（桥在重读失败时给 null）。
  static List<QueueEntry> listFrom(Object? raw) {
    if (raw is! List) return const [];
    return [for (final item in raw) ?from(item)];
  }
}

/// 队列条目状态词（气泡/管理面板共用）。
String queueSlotLabel(QueueEntry entry) =>
    entry.isNextStep ? '下一步插话' : '本轮结束后发送';
