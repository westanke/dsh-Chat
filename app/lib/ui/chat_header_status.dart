// 会话页顶栏的状态机。
//
// 顶栏上的状态永远是「一个状态点 + 一句人话」：颜色只是辅助，不单独表意。
// 结构参照 dsh-go（app/lib/ui/chat/chat_screen.dart 的 _status），只借结构：
// 文案与配色仍用本仓的 token 与既有措辞。

import '../bridge/gateway_events.dart';

/// 顶栏状态的语气。
enum ChatStatusTone {
  /// 没连上（还不是错误，只是还没连）。
  idle,

  /// 正在做：连接中、同步中、生成中。
  busy,

  /// 在等用户：等审批、等回答。
  warn,

  /// 断了：鉴权失败、连接关闭。
  error,

  /// 正常待机。
  ok,
}

/// 顶栏状态：一句人话 + 一个语气。
class ChatHeaderStatus {
  const ChatHeaderStatus(this.tone, this.label, {this.spoken});

  final ChatStatusTone tone;

  /// 顶栏上显示的那句话。
  final String label;

  /// 读屏念的那句话（审批内容、提问内容这类长文本）。
  /// Null 时读 [label]。
  final String? spoken;

  /// 读屏用词。
  String get spokenLabel => spoken ?? label;
}

/// 从连接与会话状态推出顶栏状态。
///
/// 判定顺序（先断线、再等待、最后才轮到「生成中」）：
/// 1. 没连上：连接中 / 未连接；
/// 2. 断了：鉴权失败或连接关闭 → 已断开；
/// 3. 在等用户：等审批 / 等回答；
/// 4. 正在生成；
/// 5. 一切正常：显示主机名（地址）。
ChatHeaderStatus chatHeaderStatus({
  required GatewayState connection,
  required bool streaming,
  required bool waitingApproval,
  required bool waitingAnswer,
  required String hostLabel,
  String? spoken,
}) {
  switch (connection) {
    case GatewayState.idle:
      return const ChatHeaderStatus(ChatStatusTone.idle, '未连接');
    case GatewayState.connecting:
      return const ChatHeaderStatus(ChatStatusTone.busy, '连接中');
    case GatewayState.authFailed:
    case GatewayState.closed:
      return const ChatHeaderStatus(ChatStatusTone.error, '已断开');
    case GatewayState.ready:
      break;
  }
  if (waitingApproval) {
    return ChatHeaderStatus(
      ChatStatusTone.warn,
      '等待审批',
      spoken: spoken,
    );
  }
  if (waitingAnswer) {
    return ChatHeaderStatus(
      ChatStatusTone.warn,
      '等待回答',
      spoken: spoken,
    );
  }
  if (streaming) {
    return ChatHeaderStatus(ChatStatusTone.busy, '生成中', spoken: spoken);
  }
  return ChatHeaderStatus(ChatStatusTone.ok, hostLabel, spoken: spoken);
}
