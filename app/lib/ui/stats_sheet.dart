/// 会话统计 Sheet（对照 companion ChatStatsSheet.kt）：
/// 一半指标由已加载消息本地计算（零网络请求），另一半来自桥的
/// `session-stats` 帧（服务端投影：sessionStats / tokenUsage / contextPressure）。
/// 桥太老没有这一帧时（UNKNOWN_TYPE）只显示本地那半，不报错——能力探测失败
/// 不该变成一次「出错了」的弹窗。
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../bridge/models.dart';
import '../design/tokens.dart';
import 'chat_state.dart';
import 'window_class.dart';

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

/// 服务端统计的三个容器（桥的 `session-stats` 帧）与它们的显示标题。
const Map<String, String> _serverGroups = <String, String>{
  'sessionStats': '服务端统计',
  'tokenUsage': 'Token 用量',
  'contextPressure': '上下文占用',
};

/// 纯函数：把服务端统计拍平成「分组标题 → 若干 key/value 行」。
///
/// 只取**标量叶子**，Map/List/null 一律跳过：桥把内核字段原样透传，
/// 键名与语义不在本仓的契约里，所以这里不翻译键名、不猜测单位，
/// 只做「有数字就显示数字」。空分组直接消失，不留空标题。
Map<String, List<MapEntry<String, String>>> serverStatGroups(
  Map<String, dynamic>? stats,
) {
  final out = <String, List<MapEntry<String, String>>>{};
  if (stats == null) return out;
  for (final group in _serverGroups.entries) {
    final raw = stats[group.key];
    if (raw is! Map) continue;
    final rows = <MapEntry<String, String>>[];
    for (final e in raw.entries) {
      final v = e.value;
      final text = switch (v) {
        int() => '$v',
        double() =>
          v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2),
        bool() => v ? '是' : '否',
        String() => v,
        _ => null,
      };
      if (text == null) continue;
      rows.add(MapEntry<String, String>('${e.key}', text));
    }
    if (rows.isNotEmpty) out[group.value] = rows;
  }
  return out;
}

/// 从当前会话消息 + 服务端投影计算统计并弹出底部 Sheet。
void showChatStatsSheet(
  BuildContext context,
  ChatState state,
  DsColors colors,
) {
  final c = colors;
  // 打开就拉一次服务端统计；失败静默（老桥没这一帧是常态，不是错误）。
  unawaited(state.loadServerStats());
  showModalBottomSheet<void>(
    context: context,
    constraints: modalSheetConstraints(context),
    backgroundColor: c.bgLayer1,
    builder: (context) => AnimatedBuilder(
      animation: state,
      builder: (context, _) => StatsBody(state: state, colors: c),
    ),
  );
}

class StatsBody extends StatelessWidget {
  const StatsBody({super.key, required this.state, required this.colors});

  final ChatState state;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final local = chatStatsOf(state.messages);
    final server = serverStatGroups(state.serverStats);
    return SafeArea(
      child: SingleChildScrollView(
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
                '本地统计由已加载消息计算，不产生网络请求；'
                '服务端统计来自桥的 session-stats 投影。',
                style: DsTypography.small.copyWith(color: c.labelSecondary),
              ),
              for (final group in server.entries) ...[
                const SizedBox(height: DsSpacing.blockGap),
                _GroupTitle(title: group.key, colors: c),
                for (final row in group.value)
                  _StatRow(label: row.key, value: row.value, colors: c),
              ],
              const SizedBox(height: DsSpacing.blockGap),
              _GroupTitle(title: '本地统计', colors: c),
              for (final entry in local.entries)
                _StatRow(
                  label: entry.key,
                  value: '${entry.value}',
                  colors: c,
                ),
              if (state.serverStats == null)
                Padding(
                  padding: const EdgeInsets.only(top: DsSpacing.liGap),
                  child: Text(
                    '服务端统计不可用（桥未提供 session-stats，或尚未加载完）。',
                    style: DsTypography.small.copyWith(
                      color: c.labelTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.title, required this.colors});

  final String title;
  final DsColors colors;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: DsTypography.smallStrong.copyWith(color: colors.labelPrimary),
  );
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.colors,
  });

  final String label;
  final String value;
  final DsColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DsSpacing.liGap),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: DsTypography.small.copyWith(color: c.labelSecondary),
            ),
          ),
          const SizedBox(width: DsSpacing.liGap),
          Text(
            value,
            style: DsTypography.smallStrong.copyWith(color: c.labelPrimary),
          ),
        ],
      ),
    );
  }
}
