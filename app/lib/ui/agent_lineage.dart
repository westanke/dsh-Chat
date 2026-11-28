/// 子代理谱系：从 `projections.values.subagentCatalog` 的平铺列表还原树。
/// 可选谱系键缺失时按单层 root 处理；纯投影渲染，不发新帧。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/projections.dart';
import '../design/tokens.dart';
import 'chat_state.dart';
import 'subagent_history_page.dart';
import 'window_class.dart';

/// 谱系节点的四种活动态（真实投影未必有活动信息，缺省归 idle）。
enum AgentLineageStatus {
  running('运行中'),
  completed('完成'),
  failed('失败'),
  idle('空闲');

  const AgentLineageStatus(this.label);

  final String label;
}

/// 谱系中的一个子代理节点；[children] 只读。
class AgentLineageNode {
  AgentLineageNode._(this.parentId, this.rootId, this.depth, _LineageDraft d)
      : id = d.id,
        status = d.status,
        title = d.title,
        agentName = d.agentName,
        mode = d.mode.isEmpty ? 'unknown' : d.mode,
        createdAt = d.createdAt,
        lastActivity = d.lastActivity,
        lastActiveAt = d.lastActiveAt,
        durationMs = d.durationMs;

  /// 子会话 id（投影兼容旧键 sessionId 后统一到这里）。
  final String id;

  /// 解析成功且未成环的父 id；被当作 root 时为空串。
  final String parentId;

  /// 所属树的根 id（由父子链重算）。
  final String rootId;

  /// 树深度，root 为 0；UI 每层缩进 16dp。
  final int depth;

  final AgentLineageStatus status;

  /// 优先投影 title，其次 label。
  final String title;

  /// 投影 agentName，其次 name。
  final String agentName;

  /// 原样保留的 mode（one-shot / external / continuable / unknown）。
  final String mode;

  final int? createdAt;

  /// 最近活动文字 / 时间（时间已归一到 epoch 毫秒）/ 耗时毫秒。
  final String? lastActivity;
  final int? lastActiveAt;
  final int? durationMs;

  /// 直接子代理（按投影顺序）。
  final List<AgentLineageNode> children = [];

  /// 名称：title → agentName → `子会话 <短 id>`。
  String get displayName {
    if (title.isNotEmpty) return title;
    if (agentName.isNotEmpty) return agentName;
    if (id.length <= 8) return '子会话 $id';
    return '子会话 ${id.substring(0, 8)}';
  }

  /// 打开历史页所需的最小协议模型。
  SubagentRow toSubagentRow() => SubagentRow(
        id: id,
        mode: mode,
        label: title.isNotEmpty ? title : agentName,
        createdAt: createdAt,
      );
}

/// 一棵或多棵子代理谱系。
class AgentLineage {
  const AgentLineage._(this.roots, this.total);

  /// 空谱系（无投影 / 无子代理 / 数据不可解析）。
  static const AgentLineage empty = AgentLineage._(<AgentLineageNode>[], 0);

  /// 全部 root，按投影目录顺序；[total] 为去重后的节点总数。
  final List<AgentLineageNode> roots;
  final int total;

  bool get isEmpty => total == 0;

  /// 先序遍历：父节点一定排在子节点之前，UI 直接按此顺序铺行。
  Iterable<AgentLineageNode> get nodes sync* {
    final stack = <AgentLineageNode>[...roots.reversed];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      yield node;
      for (var i = node.children.length - 1; i >= 0; i--) {
        stack.add(node.children[i]);
      }
    }
  }

  /// 从首屏 history 的 projections 构建；投影缺席/形状不对时返回 [empty]。
  static AgentLineage fromProjections(Map<String, dynamic>? projections) {
    final values = projections?['values'];
    if (values is! Map) return empty;
    final raw = values['subagentCatalog'];
    if (raw is! List) return empty;
    final entries = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      entries.add({for (final kv in item.entries) '${kv.key}': kv.value});
    }
    return fromCatalog(entries);
  }

  /// 从平铺目录构建树：缺 parent / parent 不存在 / 自指都按 root 处理；
  /// 父子成环时断开当前节点的父边，保证遍历终止且不丢节点。
  static AgentLineage fromCatalog(List<Map<String, dynamic>> entries) {
    final drafts = <_LineageDraft>[];
    final seen = <String>{};
    for (final entry in entries) {
      final id = _firstString(entry, const ['id', 'sessionId']);
      if (id.isEmpty || !seen.add(id)) continue;
      final parent =
          _firstString(entry, const ['parentId', 'parent', 'parentSessionId']);
      final startedAt = _firstInt(entry, const ['startedAt']);
      final finishedAt = _firstInt(entry, const ['finishedAt']);
      drafts.add(_LineageDraft(
        id,
        parent,
        _firstString(entry, const ['title', 'label', 'subject']),
        _firstString(entry, const ['agentName', 'name']),
        _firstString(entry, const ['mode']),
        _firstInt(entry, const ['createdAt']),
        _statusOf(_firstString(entry, const ['status', 'phase', 'state'])),
        _firstString(
            entry, const ['lastActivity', 'activity', 'currentActivity']),
        _epochMillis(_firstInt(
            entry, const ['lastActiveAt', 'lastActivityAt', 'updatedAt'])),
        _durationOf(entry, startedAt, finishedAt),
      ));
    }
    if (drafts.isEmpty) return empty;

    final byId = {for (final d in drafts) d.id: d};
    final parentOf = <String, String?>{};
    for (final d in drafts) {
      parentOf[d.id] = d.rawParent.isNotEmpty &&
              d.rawParent != d.id &&
              byId.containsKey(d.rawParent)
          ? d.rawParent
          : null;
    }

    // 防环：沿父链上溯，重复访问说明成环，断开当前节点的父边。
    for (final d in drafts) {
      final visited = <String>{d.id};
      var parent = parentOf[d.id];
      while (parent != null) {
        if (!visited.add(parent)) {
          parentOf[d.id] = null;
          break;
        }
        parent = parentOf[parent];
      }
    }

    final childrenOf = <String, List<_LineageDraft>>{};
    final rootDrafts = <_LineageDraft>[];
    for (final d in drafts) {
      final parent = parentOf[d.id];
      if (parent == null) {
        rootDrafts.add(d);
      } else {
        childrenOf.putIfAbsent(parent, () => []).add(d);
      }
    }

    AgentLineageNode build(_LineageDraft d, int depth, String rootId) {
      final node = AgentLineageNode._(parentOf[d.id] ?? '', rootId, depth, d);
      final children = childrenOf[d.id];
      if (children != null) {
        for (final child in children) {
          node.children.add(build(child, depth + 1, rootId));
        }
      }
      return node;
    }

    final roots = <AgentLineageNode>[
      for (final root in rootDrafts) build(root, 0, root.id),
    ];
    return AgentLineage._(List.unmodifiable(roots), drafts.length);
  }
}

class _LineageDraft {
  _LineageDraft(this.id, this.rawParent, this.title, this.agentName,
      this.mode, this.createdAt, this.status, this.lastActivity,
      this.lastActiveAt, this.durationMs);

  final String id, rawParent, title, agentName, mode;
  final int? createdAt;
  final AgentLineageStatus status;
  final String? lastActivity;
  final int? lastActiveAt, durationMs;
}

// ---------- 容错解析 ----------

String _firstString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

int? _firstInt(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed =
          int.tryParse(value.trim()) ?? double.tryParse(value.trim())?.toInt();
      if (parsed != null) return parsed;
    }
  }
  return null;
}

/// 活动时间可能是秒或毫秒；小于 1e11 的按秒处理。
int? _epochMillis(int? value) {
  if (value == null) return null;
  return value < 100000000000 ? value * 1000 : value;
}

int? _durationOf(Map<String, dynamic> map, int? startedAt, int? finishedAt) {
  final explicit =
      _firstInt(map, const ['durationMs', 'elapsedMs', 'totalMs']);
  if (explicit != null) return explicit < 0 ? null : explicit;
  if (startedAt == null || finishedAt == null) return null;
  final elapsed = finishedAt - startedAt;
  return elapsed < 0 ? null : elapsed;
}

AgentLineageStatus _statusOf(String raw) {
  switch (raw.toLowerCase()) {
    case 'running':
    case 'active':
    case 'in_progress':
    case 'in-progress':
    case 'working':
    case 'busy':
    case 'streaming':
      return AgentLineageStatus.running;
    case 'completed':
    case 'complete':
    case 'done':
    case 'success':
    case 'succeeded':
    case 'finished':
    case 'ok':
      return AgentLineageStatus.completed;
    case 'failed':
    case 'failure':
    case 'error':
    case 'errored':
    case 'aborted':
    case 'cancelled':
    case 'canceled':
      return AgentLineageStatus.failed;
    default:
      return AgentLineageStatus.idle;
  }
}

// ---------- 展示格式化 ----------

/// 耗时展示：`500 毫秒` / `4 秒` / `1 分 5 秒` / `1 小时 2 分`。
String formatAgentLineageDuration(int milliseconds) {
  if (milliseconds <= 0) return '0 秒';
  if (milliseconds < 1000) return '$milliseconds 毫秒';
  final seconds = (milliseconds / 1000).round();
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  final restSeconds = seconds % 60;
  if (minutes < 60) {
    return restSeconds == 0 ? '$minutes 分' : '$minutes 分 $restSeconds 秒';
  }
  final hours = minutes ~/ 60;
  final restMinutes = minutes % 60;
  return restMinutes == 0 ? '$hours 小时' : '$hours 小时 $restMinutes 分';
}

/// 最近活动展示：`刚刚` / `2 分钟前` / `3 小时前` / `5 天前`。
String formatAgentLineageAgo(int epochMillis, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).millisecondsSinceEpoch - epochMillis;
  if (diff <= 0) return '刚刚';
  final minutes = diff ~/ 60000;
  if (minutes < 1) return '刚刚';
  if (minutes < 60) return '$minutes 分钟前';
  final hours = minutes ~/ 60;
  return hours < 24 ? '$hours 小时前' : '${hours ~/ 24} 天前';
}

// ---------- 底部 Sheet ----------

/// 打开谱系底部面板；点节点先收起面板，再进只读历史页。
void showAgentLineage(
  BuildContext context,
  ChatState state,
  DsColors colors,
) {
  showModalBottomSheet<void>(
    context: context,
    constraints: modalSheetConstraints(context),
    backgroundColor: colors.bgLayer1,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(DsSpacing.settingsCardRadius),
      ),
    ),
    builder: (sheetContext) => AgentLineageSheet(
      lineage: AgentLineage.fromProjections(state.projections),
      colors: colors,
      onOpen: (node) {
        final gateway = state.gateway;
        final leadId = state.sessionId;
        if (leadId == null || leadId.isEmpty) return;
        Navigator.of(sheetContext).pop();
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => SubagentHistoryPage(
            gateway: gateway,
            leadSessionId: leadId,
            subagent: node.toSubagentRow(),
            colors: colors,
          ),
        ));
      },
    ),
  );
}

/// 谱系渲染体（标题 + 总数 + 缩进树 + 空态）。
class AgentLineageSheet extends StatelessWidget {
  const AgentLineageSheet({
    super.key,
    required this.lineage,
    required this.colors,
    this.onOpen,
  });

  final AgentLineage lineage;
  final DsColors colors;

  /// 点节点回调；为空时只展示不可点（测试与只读嵌入用）。
  final ValueChanged<AgentLineageNode>? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(DsSpacing.screenPad,
            DsSpacing.blockGap, DsSpacing.screenPad, DsSpacing.blockGap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.account_tree_outlined,
                  size: DsSpacing.fabIconSize, color: c.brand),
              const SizedBox(width: DsSpacing.actionIconGap),
              Text('子代理',
                  style: DsTypography.h4.copyWith(color: c.labelPrimary)),
              const SizedBox(width: DsSpacing.liGap),
              Text('共 ${lineage.total} 个',
                  style: DsTypography.caption.copyWith(color: c.labelTertiary)),
            ]),
            const SizedBox(height: DsSpacing.liGap),
            Text('按父子关系缩进展示；点节点查看只读历史。',
                style: DsTypography.small.copyWith(color: c.labelSecondary)),
            const SizedBox(height: DsSpacing.blockGap),
            if (lineage.isEmpty)
              _empty(c)
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final node in lineage.nodes) _node(c, node),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _empty(DsColors c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: DsSpacing.blockGap),
        child: Column(children: [
          Icon(Icons.account_tree_outlined,
              size: DsSpacing.fabSize, color: c.labelTertiary),
          const SizedBox(height: DsSpacing.liGap),
          Text('这个会话还没有子代理',
              style: DsTypography.smallStrong.copyWith(color: c.labelSecondary)),
          const SizedBox(height: DsSpacing.nestedListGap),
          Text('子代理出现后，这里会按父子关系展示它们的谱系。',
              textAlign: TextAlign.center,
              style: DsTypography.caption.copyWith(color: c.labelTertiary)),
        ]),
      );

  Widget _node(DsColors c, AgentLineageNode node) {
    final meta = <String>[node.status.label];
    final activity = node.lastActivity?.trim() ?? '';
    if (activity.isNotEmpty) meta.add('最近：$activity');
    final duration = node.durationMs;
    if (duration != null) {
      meta.add('耗时 ${formatAgentLineageDuration(duration)}');
    }
    final lastActiveAt = node.lastActiveAt;
    if (lastActiveAt != null) {
      meta.add('活跃于 ${formatAgentLineageAgo(lastActiveAt)}');
    }
    final open = onOpen;
    return InkWell(
      onTap: open == null ? null : () => open(node),
      borderRadius: BorderRadius.circular(DsSpacing.settingsCardRadius),
      child: Padding(
        padding: EdgeInsets.fromLTRB(node.depth * DsSpacing.blockGap,
            DsSpacing.cellPadV, 0, DsSpacing.cellPadV),
        child: Row(children: [
          Container(
            width: DsSpacing.drawerStatusDot,
            height: DsSpacing.drawerStatusDot,
            decoration: BoxDecoration(
                color: _statusColor(c, node.status), shape: BoxShape.circle),
          ),
          const SizedBox(width: DsSpacing.actionIconGap),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(node.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      DsTypography.smallStrong.copyWith(color: c.labelPrimary)),
              if (node.agentName.isNotEmpty &&
                  node.agentName != node.displayName)
                Text(node.agentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DsTypography.caption
                        .copyWith(color: c.labelSecondary)),
              const SizedBox(height: DsSpacing.nestedListGap),
              Text(meta.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DsTypography.caption.copyWith(color: c.labelTertiary)),
            ]),
          ),
          if (open != null)
            Icon(Icons.chevron_right,
                size: DsSpacing.actionIconSize, color: c.labelTertiary),
        ]),
      ),
    );
  }
}

Color _statusColor(DsColors c, AgentLineageStatus status) => switch (status) {
      AgentLineageStatus.running => c.brand,
      AgentLineageStatus.completed => c.chatStatusOk,
      AgentLineageStatus.failed => c.danger,
      AgentLineageStatus.idle => c.labelTertiary,
    };
