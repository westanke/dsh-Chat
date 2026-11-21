/// 斜杠命令面板的数据面：应用级命令、宿主命令的中文 face、会话技能，
/// 三层合成一张表并按固定顺序排列（与 dsh-go 的 `commands_state.dart` 对齐）。
///
/// 为什么客户端要自己带一层中文：桥 `commands` 帧透传的是内核描述（英文），
/// 而官方 Web（`dsh-client-ui-commands` 的 zh 字典）与 dsh-go 都在客户端按
/// `definitionId` 换成中文。本文件把那份字典抄到 Dart 侧，文案一字不改。
library;

import 'content.dart';

/// 内核端点名：会话可见技能目录（`skills/list`，入参 `request:{sessionId}`）。
/// 桥侧需在 KERNEL_ALLOWLIST 放行（scope `chat.read`）才出现在端点目录里。
const String kSkillsListEndpoint = 'skills/list';

/// 面板顺序（照 dsh-go 的 `_order`）：客户端功能在前，其后 first-party
/// 命令，最后是其余插件命令与技能（未列名的按名字排）。
const List<String> kSlashOrder = [
  'new',
  'model',
  'compact',
  'permission',
  'plan',
  'goal',
  'feedback',
  'export',
  'features',
];

/// 宿主的 `/export` 让浏览器下载 ZIP，App 拿不到文件——隐藏它，
/// 用客户端自己的 export（走系统分享/剪贴板）顶替。
const Set<String> kHiddenHostCommands = {'export'};

/// first-party 命令的中文 face：`definitionId → 名称/中文名/描述/参数占位`。
/// 文案与 `dsh-client-ui-commands` 的 zh 字典、dsh-go 的 `app_zh.arb` 一致。
typedef SlashFace = ({
  String name,
  String label,
  String description,
  String? hint,
});

const Map<String, SlashFace> _facesByDefinition = {
  '@deepseek-ai/dsh-command-compact': (
    name: 'compact',
    label: '压缩',
    description: '压缩以上对话内容，腾出上下文',
    hint: null,
  ),
  '@deepseek-ai/dsh-permission-presets': (
    name: 'permission',
    label: '权限',
    description: '切换权限预设（沙箱模式与审批策略）',
    hint: '<预设名>',
  ),
  '@deepseek-ai/dsh-plan-mode': (
    name: 'plan',
    label: '计划',
    description: '进入或退出计划模式',
    hint: '[off | 要求]',
  ),
  '@deepseek-ai/dsh-command-goal': (
    name: 'goal',
    label: '目标',
    description: '设置或查看长期任务目标',
    hint: '[目标 | clear | pause | resume]',
  ),
  '@deepseek-ai/dsh-command-feedback': (
    name: 'feedback',
    label: '反馈',
    description: '发送关于当前对话的反馈',
    hint: '<内容>',
  ),
};

/// 旧桥/插件副本不给 `definitionId` 时按命令名兜底认领同一份 face。
final Map<String, SlashFace> _facesByName = {
  for (final f in _facesByDefinition.values) f.name: f,
};

/// 客户端自带功能：服务端不认识这些名字（发送出去会 404），必须本地执行。
List<SlashCommand> appSlashCommands() => const [
  SlashCommand(
    name: 'new',
    label: '新对话',
    description: '开始一个新对话',
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'model',
    label: '模型',
    description: '切换模型与思考深度',
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'export',
    label: '导出日志',
    description: '把这个对话的完整记录打包成 ZIP，分享或存到「下载」',
    kind: SlashCommandKind.app,
  ),
  SlashCommand(
    name: 'features',
    label: '全部功能',
    description: '官方网页版每项功能的入口',
    kind: SlashCommandKind.app,
  ),
];

/// 宿主命令套中文 face：命中 first-party 就换掉 label/description/参数占位，
/// 未命中（插件自定义命令）保留内核原文。参数提示只在命令本身要参数时给，
/// 避免把「内核没声明参数」的命令硬加上占位。
SlashCommand localizeHostCommand(SlashCommand c) {
  final face = _facesByDefinition[c.definitionId] ?? _facesByName[c.name];
  if (face == null) return c;
  return SlashCommand(
    name: c.name,
    label: face.label,
    description: face.description,
    inputHint: c.takesInput ? (face.hint ?? c.inputHint) : null,
    definitionId: c.definitionId,
    builtin: c.builtin,
  );
}

/// 桥 `commands` 帧收敛体 → 面板宿主行（去隐藏项 + 中文化）。
List<SlashCommand> paletteHostCommands(Iterable<SlashCommand> host) => [
  for (final c in host)
    if (!kHiddenHostCommands.contains(c.name)) localizeHostCommand(c),
];

/// 内核 `skills/list` 的返回值 → 技能行。
/// 形状：`{skills: [{name, description, whenToUse?, modelInvocable?}]}`
/// （也接受裸数组，便于单测与旧内核）。缺名字的条目跳过。
List<SlashCommand> paletteSkillCommands(Object? value) {
  final raw = value is Map ? value['skills'] : value;
  if (raw is! List) return const [];
  final out = <SlashCommand>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final name = item['name'];
    if (name is! String || name.isEmpty) continue;
    out.add(
      SlashCommand(
        name: name,
        label: name,
        description: item['description'] is String
            ? item['description'] as String
            : '',
        kind: SlashCommandKind.skill,
        whenToUse: item['whenToUse'] is String
            ? item['whenToUse'] as String
            : null,
      ),
    );
  }
  return out;
}

/// 三层合并：客户端功能 → 宿主 → 技能。
/// [host] 应是已过 [paletteHostCommands] 的清单（中文化 + 去隐藏项）。
/// 同名以先出现者为准（app 压宿主、宿主压技能，与 dsh-go 同口径），
/// 随后按 [kSlashOrder] 排；未列名的（插件命令、技能）按名字排在末尾。
List<SlashCommand> mergePaletteCommands({
  required List<SlashCommand> host,
  List<SlashCommand> skills = const [],
}) {
  final byName = <String, SlashCommand>{};
  for (final c in [...appSlashCommands(), ...host, ...skills]) {
    byName.putIfAbsent(c.name, () => c);
  }
  final rank = <String, int>{
    for (var i = 0; i < kSlashOrder.length; i++) kSlashOrder[i]: i,
  };
  final ordered = <SlashCommand>[];
  final rest = <SlashCommand>[];
  for (final c in byName.values) {
    (rank.containsKey(c.name) ? ordered : rest).add(c);
  }
  ordered.sort((a, b) => rank[a.name]!.compareTo(rank[b.name]!));
  rest.sort((a, b) => a.name.compareTo(b.name));
  return [...ordered, ...rest];
}

/// `q` 是否为 `text` 的子序列（`gol` 命中 `goal`，与 dsh-go 同级回退）。
bool _isSubsequence(String q, String text) {
  var i = 0;
  for (var j = 0; j < text.length && i < q.length; j++) {
    if (text[j] == q[i]) i++;
  }
  return i == q.length;
}

/// 面板过滤：裸名前缀 → 中文名前缀 → 裸名/中文名包含 → 子序列。
/// 同级保持传入顺序（稳定），空查询回全量（v1.0.11 教训：不截断）。
List<SlashCommand> filterPaletteCommands(
  Iterable<SlashCommand> commands,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return List.of(commands);
  final byName = <SlashCommand>[];
  final byLabel = <SlashCommand>[];
  final contains = <SlashCommand>[];
  final fuzzy = <SlashCommand>[];
  for (final c in commands) {
    final name = c.name.toLowerCase();
    final label = c.displayLabel.toLowerCase();
    if (name.startsWith(q)) {
      byName.add(c);
    } else if (label.startsWith(q)) {
      byLabel.add(c);
    } else if (name.contains(q) || label.contains(q)) {
      contains.add(c);
    } else if (_isSubsequence(q, name)) {
      // 子序列只对裸名（对齐 dsh-go 的 score：`gol` 命中 goal）；中文名
      // 不参与模糊匹配，否则「权」这类单字会把一堆命令拖进来。
      fuzzy.add(c);
    }
  }
  return [...byName, ...byLabel, ...contains, ...fuzzy];
}

/// 精确解析：裸名或中文名完全相等（dsh-go 的 `resolveSlashCommand`，
/// 让用户敲「/目标」也能直接选中）。
SlashCommand? resolvePaletteCommand(
  Iterable<SlashCommand> commands,
  String token,
) {
  final t = token.trim().toLowerCase();
  if (t.isEmpty) return null;
  for (final c in commands) {
    if (c.name.toLowerCase() == t || c.displayLabel.toLowerCase() == t) {
      return c;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// 输入解析 / 面板状态 / 点选语义
//
// 这一段是 dsh-go `slash_palette.dart` + `commands_state.dart` 的逐条移植：
// 面板不是「一个列表」，而是三态（候选 / 参数提示 / 不显示），点选也不是
// 「总是插入」——无参宿主命令点一下就直接执行。只有把这几条搬全，面板的
// 手感才和 dsh-go 一致（此前只搬了条目与文案，缺的正是这一层）。
// ---------------------------------------------------------------------------

/// 指令草稿：`/` 后的名字（可能为空或只打了半截）+ 名字之后的全部文本
/// （含分隔空白）。`rest == null` 表示还在打名字，尚未出现空白。
class SlashDraft {
  const SlashDraft(this.token, this.rest);

  final String token;
  final String? rest;

  bool get hasArgs => rest != null;
}

/// 把输入框内容解析成指令草稿；`/` 不是行首第一个非空白字符时返回 null。
SlashDraft? parseSlashInput(String text) {
  final t = text.trimLeft();
  if (!t.startsWith('/')) return null;
  final m = RegExp(r'\s').firstMatch(t);
  if (m == null) return SlashDraft(t.substring(1), null);
  return SlashDraft(t.substring(1, m.start), t.substring(m.start));
}

/// 面板三态。
sealed class PaletteContent {
  const PaletteContent();
}

/// 不显示面板。
final class PaletteNone extends PaletteContent {
  const PaletteNone();
}

/// 候选列表（名字还没打完）。
final class PaletteMatches extends PaletteContent {
  const PaletteMatches({
    required this.matches,
    required this.typed,
    required this.hasSuffix,
    required this.query,
  });

  final List<SlashCommand> matches;

  /// 已经打了半个名字：此时第一行是「回车就会选中」的那行（面板高亮它）。
  final bool typed;

  /// 光标后面还有文本（在句子中间补全）。
  final bool hasSuffix;

  /// 用户敲的片段，空列表时用于「没有匹配的命令 ‹片段›」。
  final String query;
}

/// 参数提示（名字已完整且该命令要参数）：单行，不可点。
final class PaletteHint extends PaletteContent {
  const PaletteHint(this.command);

  final SlashCommand command;
}

/// 当前输入该显示哪种面板——与 dsh-go `PaletteContent.of` 同判据。
PaletteContent paletteContentOf({
  required Iterable<SlashCommand> commands,
  required String text,
  int? caret,
}) {
  final draft = parseSlashInput(text);
  if (draft == null) return const PaletteNone();
  final at = (caret ?? text.length).clamp(0, text.length);
  final suffix = text.substring(at);
  if (!draft.hasArgs) {
    return PaletteMatches(
      matches: filterPaletteCommands(commands, draft.token),
      typed: draft.token.isNotEmpty,
      hasSuffix: suffix.isNotEmpty,
      query: draft.token,
    );
  }
  final rest = draft.rest ?? '';
  // 已经有参数 / 光标后有字 / 多行草稿：这是在写内容，不是在挑命令。
  if (rest.trim().isNotEmpty || suffix.isNotEmpty || text.contains('\n')) {
    return const PaletteNone();
  }
  final command = resolvePaletteCommand(commands, draft.token);
  if (command == null || !command.takesInput) return const PaletteNone();
  return PaletteHint(command);
}

/// 补全时保留哪一段：已知命令名整段替换，未知名字只替换光标之前的部分，
/// 光标之后的文本原样保留（dsh-go `slashCompletionContext`）。
({int leading, String suffix}) slashCompletionContext(
  Iterable<SlashCommand> commands,
  String text,
  int caret,
) {
  final leading = text.length - text.trimLeft().length;
  final at = caret.clamp(0, text.length);
  final full = parseSlashInput(text);
  final end =
      full != null && resolvePaletteCommand(commands, full.token) != null
      ? leading + 1 + full.token.length
      : at;
  return (leading: leading, suffix: text.substring(end.clamp(0, text.length)));
}

/// 点选这一行是「插入到输入框」还是「直接执行」。
bool slashPickInsertsText(SlashCommand command, {required bool hasSuffix}) =>
    hasSuffix ||
    command.kind == SlashCommandKind.skill ||
    (command.kind == SlashCommandKind.host && command.takesInput);

/// 点选后的输入框内容与光标位置；null = 这一行应当直接执行。
({String text, int caret})? slashPickCompletion(
  Iterable<SlashCommand> commands,
  SlashCommand command,
  String text,
  int caret,
) {
  final ctx = slashCompletionContext(commands, text, caret);
  if (!slashPickInsertsText(command, hasSuffix: ctx.suffix.isNotEmpty)) {
    return null;
  }
  final prefix = '${text.substring(0, ctx.leading)}/${command.name}';
  final separator = ctx.suffix.isEmpty || !RegExp(r'^\s').hasMatch(ctx.suffix)
      ? ' '
      : '';
  final out = '$prefix$separator${ctx.suffix}';
  return (text: out, caret: (prefix.length + 1).clamp(0, out.length));
}

/// 回车发送时这一行是什么意思（dsh-go `_slashFor` 的判据）。
sealed class SlashSend {
  const SlashSend();
}

/// 普通消息。
final class SlashSendMessage extends SlashSend {
  const SlashSendMessage();
}

/// 吃掉这次回车（只敲了一个 `/`，面板开着等人挑）。
final class SlashSendSwallow extends SlashSend {
  const SlashSendSwallow();
}

/// 交给宿主执行整行。
final class SlashSendRun extends SlashSend {
  const SlashSendRun(this.command, this.line);

  final SlashCommand command;
  final String line;
}

/// 选中候选第一行（名字打了一半就回车）。
final class SlashSendPick extends SlashSend {
  const SlashSendPick(this.command);

  final SlashCommand command;
}

/// 面板关闭标记的复位规则（dsh-go `_resetSlashDismissal` 同判据）：
/// 离开斜杠输入、或重新敲成裸 `/`，就清掉关闭标记让面板再弹；否则跟着文本走。
String? resetSlashDismissal(String? dismissed, String text) {
  if (dismissed == null) return null;
  final restarted = text.trim() == '/' && dismissed.trim() != '/';
  return (parseSlashInput(text) == null || restarted) ? null : text;
}

/// 回车这个动作该怎么处理（dsh-go `_slashFor` 同口径）：普通消息 / 吃掉回车
/// （只敲了裸 `/`）/ 执行整行 / 选中候选第一行。技能整行走消息，因为宿主是从
/// 正文里加载技能的，客户端当命令发会 404。
SlashSend classifySlashSend(Iterable<SlashCommand> commands, String text) {
  final draft = parseSlashInput(text);
  if (draft == null) return const SlashSendMessage();
  if (draft.token.isEmpty && !draft.hasArgs) return const SlashSendSwallow();
  final exact = resolvePaletteCommand(commands, draft.token);
  if (exact != null) {
    // 技能整行是消息：宿主从正文里加载技能，客户端不该当命令发（会 404）。
    if (exact.kind == SlashCommandKind.skill) return const SlashSendMessage();
    return SlashSendRun(exact, '/${exact.name}${draft.rest ?? ''}');
  }
  // 名字不认识但带了参数：多半是路径之类的正文。
  if (draft.hasArgs) return const SlashSendMessage();
  final matches = filterPaletteCommands(commands, draft.token);
  if (matches.isEmpty) return const SlashSendMessage();
  return SlashSendPick(matches.first);
}
