/// 抽屉里「对话内容」那一节的渲染件（从 sessions_drawer.dart 拆出，宪法 §7 控行数）。
///
/// 内容搜索的编排在 session_search.dart，这里只管把它画出来：**三种结局分开呈现**
/// ——在搜 / 没搜到 / 搜不了。为什么不能只写「没有匹配」，见 session_search.dart
/// 文件头那段部署侧限制（内核会话索引可能被 `openAt "never"` 关掉）。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/models.dart';
import '../design/tokens.dart';
import 'chat_state.dart';
import 'session_search.dart';
import 'sessions_drawer_item.dart';

/// 正文命中节：标题行（含状态）+ 命中的会话行。
///
/// [onOpen] 由抽屉传入（点命中会话时先收起抽屉再开会话）。
List<Widget> buildContentSearchSection({
  required SessionSearchController content,
  required DsColors colors,
  required ChatState state,
  required VoidCallback onOpen,
}) {
  final titleStyle = DsTypography.caption.copyWith(color: colors.drawerGroupLabel);

  Widget note(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(
      DsSpacing.drawerItemPadH,
      0,
      DsSpacing.drawerItemPadH,
      DsSpacing.drawerSectionPadBottom,
    ),
    child: Text(
      text,
      style: DsTypography.small.copyWith(color: colors.drawerGroupLabel),
    ),
  );

  // 同一会话命中多处时只出一条：抽屉是「跳到会话」的入口，重复行没有信息量。
  final seen = <String>{};
  final rows = <Widget>[];
  for (final hit in content.hits) {
    if (!seen.add(hit.sessionId)) continue;
    final session = _sessionOf(state, hit.sessionId);
    // 会话不在当前列表里（已被归档 / 属于别的根）时也留一行，但点不开：
    // 拿 id 去 openSession 只会拉回来一段空历史，反倒像「会话丢了」。
    rows.add(
      SessionsDrawerItem(
        session: session ?? _placeholderSession(hit),
        selected: hit.sessionId == state.sessionId,
        badge: session == null ? '已归档' : '正文',
        colors: colors,
        onTap: session == null
            ? null
            : () {
                onOpen();
                state.openSession(session);
              },
        subtitle: hit.snippet.isEmpty ? null : hit.snippet,
      ),
    );
  }

  final status = switch (content) {
    _ when content.busy => '搜索中…',
    _ when content.error != null => '搜索不可用：${content.error}',
    _ when content.hits.isEmpty => '没有匹配',
    _ => '${seen.length} 个会话',
  };

  return [
    Padding(
      padding: const EdgeInsets.fromLTRB(
        DsSpacing.drawerItemPadH,
        DsSpacing.drawerSectionPadTop,
        DsSpacing.drawerItemPadH,
        DsSpacing.drawerSectionPadBottom,
      ),
      child: Row(
        children: [
          Text('对话内容', style: titleStyle),
          const SizedBox(width: DsSpacing.drawerSearchIconGap),
          Expanded(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
          ),
        ],
      ),
    ),
    if (!content.busy && content.error == null) ...rows,
    // 空结果时的额外说明：本机部署关掉内核索引的话，这里永远是空的。
    if (!content.busy && content.error == null && content.hits.isEmpty)
      note('只搜到正文里的词，标题匹配见下方分组。'),
  ];
}

DshSession? _sessionOf(ChatState state, String id) {
  for (final s in state.sessions) {
    if (s.id == id) return s;
  }
  return null;
}

/// 内容命中里的会话在当前列表找不到时的占位（只为渲染一行，不能点开）。
DshSession _placeholderSession(SessionSearchHit hit) => DshSession(
  id: hit.sessionId,
  rootId: '',
  updatedAt: 0,
  running: false,
  blank: false,
  title: hit.snippet.isEmpty ? hit.sessionId : hit.snippet,
);
