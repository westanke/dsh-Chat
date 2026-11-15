/// 新建会话工作目录选择（2026-11-15 反馈「新建会话可选工作目录」）。
///
/// 入口：空态页的「工作目录」chip（chat_page.dart _Greeting，仅未发
/// 首条消息时存在）。默认「手机会话」不弹也可以直接发；选中某目录后
/// ChatState.pendingLocation 记录之，send() 首条消息走
/// session-create{rootId,cwd}（gateway_api.dart createSessionAt）。
/// 历史会话不受影响：目录在会话创建时定死，本 sheet 只管「新建」。
///
/// 候选来源（协议不吐绝对路径，见 openapi /roots 说明）：
/// - 历史会话快照的 (rootId, cwd) 去重（含跨根目录，cwdRelative 已下发）；
/// - file-list 浏览授权根目录（ws-files.ts，需要 files.read scope）。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../bridge/models.dart';
import '../design/tokens.dart';
import 'chat_state.dart';

/// 弹出目录选择 Sheet。数据取自 [state]（最近候选）与 [lister]（浏览；
/// null = state.gateway.listDirectory，测试可注入假页）。
Future<void> showSessionLocationSheet(
  BuildContext context,
  ChatState state,
  DsColors colors, {
  DirectoryLister? lister,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.bgLayer1,
    isScrollControlled: true,
    builder: (sheetContext) =>
        _LocationSheet(state: state, colors: colors, lister: lister),
  );
}

/// 目录数据获取注入点：默认走 gateway.listDirectory（file-list 帧）；
/// 测试可注入假页（sheet 不绑死网络）。
typedef DirectoryLister =
    Future<DshDirectoryPage> Function({
      String? rootId,
      String path,
      String? cursor,
    });

// ---------- 主列表：默认项 + 最近使用 + 浏览入口 ----------

class _LocationSheet extends StatelessWidget {
  const _LocationSheet({
    required this.state,
    required this.colors,
    this.lister,
  });

  final ChatState state;
  final DsColors colors;
  final DirectoryLister? lister;

  /// 最近会话目录候选：(rootId, cwd) 去重，保序（sessions 按 updatedAt
  /// 倒序，最近用过的排前）。排除当前已选中的那项（列表下方高亮显示）。
  List<SessionLocation> recentCandidates() {
    final out = <SessionLocation>[];
    final seen = <String>{};
    for (final s in state.sessions) {
      final key = '${s.rootId}\u0000${s.cwd}';
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(
        SessionLocation(
          rootId: s.rootId,
          cwd: s.cwd,
          label: locationLabel(s.cwd),
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final loc = state.pendingLocation;
    final recents = recentCandidates();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
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
                '会话工作目录',
                style: DsTypography.h4.copyWith(color: c.labelPrimary),
              ),
              const SizedBox(height: DsSpacing.liGap),
              Text(
                '新建会话默认落到「手机会话」工作区；也可以指定授权根下的'
                '某个目录。目录在会话创建时定死，历史会话不受影响。',
                style: DsTypography.small.copyWith(color: c.labelSecondary),
              ),
              const SizedBox(height: DsSpacing.blockGap),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    // 默认项：不选目录，走手机工作区（workspaceId 通道）。
                    ListTile(
                      leading: Icon(Icons.smartphone, color: c.brand),
                      title: Text(
                        '手机会话（默认）',
                        style: DsTypography.base.copyWith(
                          color: c.labelPrimary,
                        ),
                      ),
                      subtitle: Text(
                        loc == null ? '当前选择' : '点此恢复默认',
                        style: DsTypography.small.copyWith(
                          color: loc == null ? c.brand : c.labelTertiary,
                        ),
                      ),
                      trailing: loc == null
                          ? Icon(Icons.check, size: 18, color: c.brand)
                          : null,
                      onTap: () {
                        state.setPendingLocation(null);
                        Navigator.of(context).pop();
                      },
                    ),
                    if (loc != null) ...[
                      const SizedBox(height: DsSpacing.liGap),
                      // 已选目录单列高亮（不在「最近使用」里重复显示）。
                      ListTile(
                        leading: Icon(Icons.folder, color: c.brand),
                        title: Text(
                          loc.label,
                          style: DsTypography.base.copyWith(
                            color: c.labelPrimary,
                          ),
                        ),
                        subtitle: Text(
                          '当前选择',
                          style: DsTypography.small.copyWith(
                            color: c.brand,
                          ),
                        ),
                        trailing: Icon(Icons.check, size: 18, color: c.brand),
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ],
                    if (recents.isNotEmpty) ...[
                      const SizedBox(height: DsSpacing.liGap),
                      Text(
                        '最近使用',
                        style: DsTypography.small.copyWith(
                          color: c.labelTertiary,
                        ),
                      ),
                      for (final item in recents)
                        if (loc == null ||
                            item.rootId != loc.rootId ||
                            item.cwd != loc.cwd)
                          ListTile(
                            leading: Icon(Icons.folder, color: c.labelSecondary),
                            title: Text(
                              item.label,
                              style: DsTypography.base.copyWith(
                                color: c.labelPrimary,
                              ),
                            ),
                            subtitle: Text(
                              _absoluteSubtitle(item),
                              style: DsTypography.small.copyWith(
                                color: c.labelTertiary,
                              ),
                            ),
                            onTap: () {
                              state.setPendingLocation(item);
                              Navigator.of(context).pop();
                            },
                          ),
                    ],
                    const SizedBox(height: DsSpacing.liGap),
                    ListTile(
                      leading: Icon(Icons.folder_open, color: c.brand),
                      title: Text(
                        '浏览授权根目录…',
                        style: DsTypography.base.copyWith(
                          color: c.labelPrimary,
                        ),
                      ),
                      onTap: () async {
                        final picked = await Navigator.of(context)
                            .push<SessionLocation>(
                              MaterialPageRoute(
                                builder: (_) => _BrowseRootsPage(
                                  state: state,
                                  colors: c,
                                  lister: lister,
                                ),
                              ),
                            );
                        if (picked != null && context.mounted) {
                          state.setPendingLocation(picked);
                          Navigator.of(context).pop();
                        }
                      },
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

  /// 候选副标题：会话快照的绝对路径（cwdAbsolute）比 uuid rootId 可读。
  String _absoluteSubtitle(SessionLocation item) {
    for (final s in state.sessions) {
      if (s.rootId == item.rootId && s.cwd == item.cwd) {
        final abs = s.cwdAbsolute;
        if (abs != null && abs.isNotEmpty) return abs;
        break;
      }
    }
    final rid = item.rootId;
    return (rid == null || rid.isEmpty) ? '首个授权根' : rid;
  }
}

/// 目录显示名：'' = 授权根本身；否则显示相对路径。
String locationLabel(String cwd) =>
    cwd.isEmpty ? '根目录' : cwd;

// ---------- 浏览页：file-list 逐级目录 ----------

class _BrowseRootsPage extends StatefulWidget {
  const _BrowseRootsPage({
    required this.state,
    required this.colors,
    this.lister,
  });

  final ChatState state;
  final DsColors colors;
  final DirectoryLister? lister;

  @override
  State<_BrowseRootsPage> createState() => _BrowseRootsPageState();
}

class _BrowseRootsPageState extends State<_BrowseRootsPage> {
  String? rootId; // 空 = 首个授权根（file-list 语义）。
  String path = '';
  List<DshFileEntry> entries = [];
  String? nextCursor;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  DirectoryLister get _lister =>
      widget.lister ??
      ({String? rootId, String path = '', String? cursor}) =>
          widget.state.gateway.listDirectory(
            rootId: rootId,
            path: path,
            cursor: cursor,
          );

  Future<void> _load(String cursor) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await _lister(
        rootId: rootId,
        path: path,
        cursor: cursor.isEmpty ? null : cursor,
      );
      if (!mounted) return;
      setState(() {
        rootId = page.rootId;
        entries = cursor.isEmpty
            ? page.entries
            : [...entries, ...page.entries];
        nextCursor = page.nextCursor;
        loading = false;
      });
    } on RequestException catch (e) {
      if (!mounted) return;
      setState(() {
        error = '${e.code} ${e.message}';
        loading = false;
      });
    }
  }

  void _enter(DshFileEntry entry) {
    setState(() {
      path = entry.path;
      entries = [];
      nextCursor = null;
    });
    _load('');
  }

  void _up() {
    if (path.isEmpty) return;
    final idx = path.lastIndexOf('/');
    setState(() {
      path = idx < 0 ? '' : path.substring(0, idx);
      entries = [];
      nextCursor = null;
    });
    _load('');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final dirs = entries.where((e) => e.kind == 'directory').toList();
    return Scaffold(
      backgroundColor: c.bgBase,
      appBar: AppBar(
        backgroundColor: c.bgBase,
        title: Text(
          '选择工作目录',
          style: DsTypography.pageTitle.copyWith(color: c.labelPrimary),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 面包屑：根 / a / b，逐级可点回退。
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DsSpacing.screenPad,
              vertical: DsSpacing.liGap,
            ),
            child: Row(
              children: [
                Icon(Icons.folder, size: 16, color: c.brand),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    path.isEmpty ? '根目录' : path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DsTypography.small.copyWith(
                      color: c.labelPrimary,
                    ),
                  ),
                ),
                if (path.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.arrow_upward, size: 18, color: c.brand),
                    onPressed: _up,
                    tooltip: '上一级',
                  ),
              ],
            ),
          ),
          Expanded(
            child: loading && entries.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Center(
                    child: Text(
                      '读取目录失败：$error',
                      style: DsTypography.small.copyWith(
                        color: c.danger,
                      ),
                    ),
                  )
                : dirs.isEmpty
                ? Center(
                    child: Text(
                      '此目录下没有子目录',
                      style: DsTypography.small.copyWith(
                        color: c.labelTertiary,
                      ),
                    ),
                  )
                : ListView(
                    children: [
                      for (final d in dirs)
                        ListTile(
                          leading: Icon(
                            Icons.folder,
                            color: c.labelSecondary,
                          ),
                          title: Text(
                            d.name,
                            style: DsTypography.base.copyWith(
                              color: c.labelPrimary,
                            ),
                          ),
                          onTap: () => _enter(d),
                        ),
                      if (nextCursor != null)
                        ListTile(
                          title: Text(
                            loading ? '加载中…' : '加载更多',
                            style: DsTypography.small.copyWith(
                              color: c.brand,
                            ),
                          ),
                          onTap: loading
                              ? null
                              : () => _load(nextCursor!),
                        ),
                    ],
                  ),
          ),
          // 选定当前目录（'' = 根，同样合法：会话直接落授权根）。
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                DsSpacing.screenPad,
                DsSpacing.liGap,
                DsSpacing.screenPad,
                DsSpacing.blockGap,
              ),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.brand,
                  foregroundColor: c.onBrand,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => Navigator.of(context).pop(
                  SessionLocation(
                    rootId: rootId,
                    cwd: path,
                    label: locationLabel(path),
                  ),
                ),
                child: Text(
                  '在此目录新建会话',
                  style: DsTypography.base.copyWith(color: c.onBrand),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
