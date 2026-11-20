// 会话列表的行间距规则。
//
// 间距只在这里给一次：行内组件不再自带顶距，行框统一垫上去。
// 结构参照 dsh-go（app/lib/ui/chat/chat_list.dart 的 _gapBefore），
// 数值取本仓 design-tokens.md §4.12 的会话页行距阶梯。

import 'package:dshchat/design/tokens.dart';
import 'package:dshchat/ui/chat_rows.dart';

/// 这行是不是用户消息。
bool isUserRow(ChatRow? row) => row is UserRow;

/// 这行是不是「过程」：工具组、流式工具组、命令回执、流式正文。
///
/// 流式正文算过程：它紧跟在流式工具组后面，两者之间不留空。
bool isProcessRow(ChatRow? row) =>
    row is ProcessRow ||
    row is StreamingProcessRow ||
    row is CommandRow ||
    row is StreamingTextRow;

/// 这一行上方该留多少空。
///
/// 换轮 24、同一轮 8、相邻过程行 0、卡片 12、脚注 4 —— 全是 4 的倍数。
/// [previous] 为 null（列表第一行）时没有上方内容，不留空。
double chatRowGapBefore(ChatRow row, ChatRow? previous) {
  if (previous == null) return 0;
  // 用户消息：连着两条用户消息算同一段话，只留一点空。
  if (isUserRow(row)) {
    return isUserRow(previous)
        ? DsSpacing.chatGapSameTurn
        : DsSpacing.chatGapNewTurn;
  }
  // 相邻过程行之间不留空：工具组自己分行。
  if (isProcessRow(row) && isProcessRow(previous)) {
    return DsSpacing.chatGapProcess;
  }
  // 文件卡是独立的一层，比正文离得远一些。
  if (row is FilesRow) return DsSpacing.chatGapCard;
  // 轮尾行贴着上面的过程组。
  if (row is TurnEndRow) return DsSpacing.chatGapFootnote;
  return DsSpacing.chatGapSameTurn;
}
