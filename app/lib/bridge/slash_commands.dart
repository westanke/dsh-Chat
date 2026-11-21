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
