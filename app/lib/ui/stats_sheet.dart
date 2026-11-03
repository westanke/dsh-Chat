/// 会话统计 Sheet（对照 companion ChatStatsSheet.kt）：
/// 全部指标由 ChatState 已加载的消息本地计算，零网络请求；
/// 协议没有 stats 帧，这里不臆造服务端数字。
library;

import 'package:flutter/material.dart';

import '../bridge/models.dart';
import '../design/tokens.dart';
import 'chat_state.dart';

/// 纯函数：由消息列表计算统计（便于单测）。
Map<String, int> chatStatsOf(List<ChatMessage> messages) {
  var users = 0;
  var assistants = 0;
  var processes = 0;
  var errors = 0;
  var tools = 0;
  var thinks = 0;
  for (final m in messages) {
    if (m.role == 'user') {
      users++;
    } else if (m.role == 'assistant') {
      assistants++;
    } else if (m.role == 'process') {
      processes++;
    } else if (m.role == 'error') {
      errors++;
    }
    tools += m.toolCalls.length;
    if (m.reasoning.isNotEmpty) thinks++;
  }
  return <String, int>{
    '消息总数': messages.length,
    '用户消息': users,
    '助手回复': assistants,
    '工具过程组': processes,
    '错误提示': errors,
    '工具调用': tools,
    '思考块': thinks,
  };
}

/// 从当前会话消息计算统计并弹出底部 Sheet。
void showChatStatsSheet(
  BuildContext context,
  ChatState state,
  DsColors colors,
) {
  final c = colors;
  final stats = chatStatsOf(state.messages);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.bgLayer1,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          DsSpacing.screenPad,
          DsSpacing.blockGap,
          DsSpacing.screenPad,
          DsSpacing.blockGap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '会话统计',
              style: DsTypography.h4.copyWith(color: c.labelPrimary),
            ),
            const SizedBox(height: DsSpacing.liGap),
            Text(
              '由当前会话已加载的消息本地计算，不产生网络请求。',
              style: DsTypography.small.copyWith(color: c.labelSecondary),
            ),
            const SizedBox(height: DsSpacing.blockGap),
            for (final entry in stats.entries)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: DsSpacing.liGap,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      entry.key,
                      style: DsTypography.small.copyWith(
                        color: c.labelSecondary,
                      ),
                    ),
                    Text(
                      '${entry.value}',
                      style: DsTypography.smallStrong.copyWith(
                        color: c.labelPrimary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
