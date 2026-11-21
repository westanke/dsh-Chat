/// 消息 content 的部件模型：从 HistoryPage.fromEvents / models.dart 拆出
/// （宪法 §7 单文件 ≤500 行；models.dart 经由 export 继续暴露这些类型，
/// 既有 import 不受影响）。
///
/// 形状依据 dsh-remote-bridge v2.10.0：
/// - 文本/推理块：`{type:'text'|'reasoning', text}`（ChatHistoryMapping 同构）。
/// - 图片块（历史）：`{type:'image', attachment:{attachmentId:'sha256:<hex>'}}`
///   —— 历史里只存引用不存字节（kernel-services.ts:54-58 注释）；发送时才是
///   base64 内联的 PromptPart.image。
/// - 纯文本模型的图片交接（bridge attachments.ts handoffImagesForTextOnlyModel）：
///   图片落工作区 `.dsh-images/<sha256>.<ext>`，消息文本留
///   `[Image: source: <绝对路径>]` 占位（真机反馈第 8 条桌面识别回路）。
library;

/// 历史消息里的图片引用（attachmentId，字节走 REST attachments 接口取）。
class ContentImageRef {
  const ContentImageRef({required this.attachmentId});

  final String attachmentId; // 形如 'sha256:<hex>'

  factory ContentImageRef.from(Map<String, dynamic> block) {
    final att = block['attachment'];
    final id = att is Map ? att['attachmentId'] : null;
    return ContentImageRef(attachmentId: id is String ? id : '');
  }

  bool get isValid => attachmentId.isNotEmpty;
}

/// 从 content（primitive / array）提取 text+reasoning 文本与图片引用，
/// 文本规则与 companion ChatHistoryMapping.contentTextParts 一致。
class ContentParts {
  const ContentParts({
    this.text = '',
    this.reasoning = '',
    this.images = const [],
  });
  final String text;
  final String reasoning;

  /// content 数组里 type=image 的块（历史形状：attachment 引用，无字节）。
  final List<ContentImageRef> images;

  factory ContentParts.from(dynamic content) {
    String text = '';
    String reasoning = '';
    final images = <ContentImageRef>[];
    void take(String type, String? t) {
      if (t == null || t.isEmpty) return;
      if (type == 'reasoning') {
        reasoning += (reasoning.isEmpty ? '' : '\n\n') + t;
      } else {
        text += (text.isEmpty ? '' : '\n') + t;
      }
    }

    if (content is String) return ContentParts(text: content);
    if (content is List) {
      for (final block in content) {
        if (block is Map) {
          final type = (block['type'] ?? '') as String;
          if (type == 'image') {
            final ref = ContentImageRef.from(
              Map<String, dynamic>.from(block),
            );
            if (ref.isValid) images.add(ref);
            continue;
          }
          final t = block['text'];
          if (t is String) take(type, t);
        }
      }
    }
    return ContentParts(text: text, reasoning: reasoning, images: images);
  }
}

/// 图片交接占位符：`[Image: source: <绝对路径>]`，文件名是
/// `<sha256-hex>.<ext>`（bridge files.ts 校验格式 `^[0-9a-f]{64}\.[A-Za-z0-9]+$`）。
final RegExp _handoffPattern = RegExp(
  r'\[Image: source: [^\]]*?([0-9a-f]{64}\.[A-Za-z0-9]+)\s*\]',
);

/// 从消息文本提取 image-handoff 交接文件名（bare name，如
/// `3f9a….png`）；没有交接占位符返回 null。
/// 手机端用这个名字走 REST GET /api/v1/image-handoff 取回字节显示。
String? handoffImageNameOf(String text) {
  final m = _handoffPattern.firstMatch(text);
  if (m == null) return null;
  return m.group(1);
}

/// PromptContentPart（chat-adapter.ts）：文本 / 图片（base64）/ 文件回执。
class PromptPart {
  const PromptPart.text(String this.text_)
    : type = 'text',
      mediaType = null,
      data = null,
      name = null,
      receiptId = null;
  const PromptPart.image(this.mediaType, this.data, {this.name})
    : type = 'image',
      text_ = null,
      receiptId = null;

  final String type;
  final String? text_; // type=text
  final String? mediaType; // type=image（白名单 png/jpeg/webp/gif）
  final String? data; // type=image, base64 裸串
  final String? name; // type=image, 可选文件名（chat-adapter.ts:26-29）
  final String? receiptId; // type=file

  Map<String, dynamic> toJson() => switch (type) {
    'text' => {'type': 'text', 'text': text_},
    // name 非空才输出（companion 因 encodeDefaults 丢 mediaType 翻过车，
    // 这里反过来：schema 支持 name，就按 schema 发）。
    'image' => {
      'type': 'image',
      'mediaType': mediaType,
      'data': data,
      'name': ?name,
    },
    'file' => {'type': 'file', 'receiptId': receiptId},
    _ => {'type': 'text', 'text': text_ ?? ''},
  };
}

/// 斜杠命令面板的条目来源（对齐 dsh-go 的 SlashCommandKind）。
/// 面板把三类按固定顺序合成一张表：客户端自带功能 → 内核命令 → 会话技能。
enum SlashCommandKind {
  /// 桥 `commands` 帧透传的内核命令（compact/plan/goal/…）。
  host,

  /// 客户端自己实现的功能（new/model/export/features）——服务端不认识，
  /// 必须走本地动作，不能当命令发送。
  app,

  /// 当前会话可见的技能（内核 `skills/list`）。
  skill,
}

/// 斜杠命令（真机反馈 2026-11-04 第 3 项）。
/// bridge `commands` 帧应答 data.commands：`{name, description, input?}`；
/// 桥 v2.11.0 起条目另带可选 `definitionId` / `builtin`（issue #1 适配，
/// 宽容解析：旧桥缺省 null/false）。name 已含前导斜杠还是裸名——
/// ws-commands.ts 的 listCommands 直接透传内核 ChatCommandDescriptor，
/// companion 里命令面板按裸名展示、发送时拼 `/`。
/// （listCommands 在会话激活不了时回 []，不报错——chat-adapter.ts:1190-1200。）
class SlashCommand {
  const SlashCommand({
    required this.name,
    required this.description,
    this.inputHint,
    this.definitionId,
    this.builtin = false,
    this.label,
    this.kind = SlashCommandKind.host,
    this.whenToUse,
  });

  final String name; // 裸名，如 'model'
  final String description;
  final String? inputHint; // 需要参数时的提示

  /// 内核命令定义 id（桥 v2.11.0 commands 帧新增）。
  final String? definitionId;

  /// 是否内置命令（桥 v2.11.0 commands 帧新增）。
  final bool builtin;

  /// 面板标题的中文名（first-party 命令与客户端功能；技能为 null）。
  /// 口径与 dsh-go 的 `SlashCommand.label` 一致——内核描述是英文，面板
  /// 按 definitionId 换成官方 Web 的中文字典（bridge/slash_commands.dart）。
  final String? label;

  /// 条目来源（决定点选后「插入文本」还是「本地执行」）。
  final SlashCommandKind kind;

  /// 技能的额外适用场景说明（`skills/list` 的 whenToUse，可空）。
  final String? whenToUse;

  /// 面板主标题：有中文名用中文名，否则回退裸名。
  String get displayLabel => (label != null && label!.isNotEmpty) ? label! : name;

  /// 需要参数（面板给 hint 占位；点选后只插入不发送）。
  bool get takesInput => inputHint != null;

  factory SlashCommand.from(Map<String, dynamic> j) {
    // 桥 v2.11.0 起 input 是对象 `{hint, attachments}`（见 ws-protocol.ts
    // CommandDescriptorView）；更早的桥/no-hint 命令直接给字符串或 null。
    // 修复：此前只认 String，Map 形状的 hint 恒丢（面板从不显示参数提示）。
    final input = j['input'];
    final String? hint;
    if (input is Map) {
      hint = input['hint'] is String ? input['hint'] as String : null;
    } else {
      hint = input is String ? input : null;
    }
    return SlashCommand(
      name: ((j['name'] ?? '') as String).replaceAll(RegExp(r'^/'), ''),
      description: (j['description'] ?? '') as String,
      inputHint: hint,
      definitionId: j['definitionId'] is String
          ? j['definitionId'] as String
          : null,
      builtin: j['builtin'] == true,
    );
  }

  /// 输入框里从 `/abc` 过滤本命令：前缀匹配。
  bool matchesQuery(String q) =>
      q.isEmpty || name.toLowerCase().startsWith(q.toLowerCase());
}

/// 内置命令的 en/zh 别名（桥 v2.11.0 commands 帧 `builtinTokens`，帧级；
/// chat-adapter.ts:219 BUILTIN_COMMAND_TOKENS：goal→目标、plan→计划、
/// feedback→反馈、compact→压缩、permission→权限、export→导出）。
class BuiltinCommandTokens {
  const BuiltinCommandTokens({required this.en, required this.zh});

  final String en;
  final String zh;

  factory BuiltinCommandTokens.from(Map<String, dynamic> j) =>
      BuiltinCommandTokens(
        en: j['en'] is String ? j['en'] as String : '',
        zh: j['zh'] is String ? j['zh'] as String : '',
      );
}

/// `commands` 帧应答收敛。
class SlashCommandList {
  const SlashCommandList({required this.commands, this.builtinTokens = const {}});

  /// 全命令清单为空的面板占位（拉取失败路径复用，m04149 语义：不报错）。
  static const SlashCommandList empty = SlashCommandList(commands: []);

  final List<SlashCommand> commands;

  /// 键 = 命令裸名（goal/plan/...）。旧桥无此帧级字段 → 空表，中文过滤退化为仅前缀。
  final Map<String, BuiltinCommandTokens> builtinTokens;

  static SlashCommandList from(Map<String, dynamic> data) {
    final raw = data['commands'];
    final list = <SlashCommand>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          list.add(
            SlashCommand.from(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final tokens = <String, BuiltinCommandTokens>{};
    final tokensRaw = data['builtinTokens'];
    if (tokensRaw is Map) {
      for (final e in tokensRaw.entries) {
        if (e.value is Map) {
          tokens[e.key as String] = BuiltinCommandTokens.from(
            Map<String, dynamic>.from(e.value as Map),
          );
        }
      }
    }
    return SlashCommandList(commands: list, builtinTokens: tokens);
  }

  /// 输入片段过滤命令（issue #1 命令面板本地化）：裸名前缀之外，内置命令
  /// 再按 zh 别名前缀匹配（敲「目标」能过滤出 /goal）；en 别名同时参与
  /// （敲中文输入法残留英文也命中）。空片段回全量（v1.0.11 教训：不截断）。
  List<SlashCommand> matching(String q) {
    final t = q.trim();
    if (t.isEmpty) return List.of(commands);
    final lower = t.toLowerCase();
    return [
      for (final c in commands)
        if (c.matchesQuery(t) ||
            builtinTokens[c.name]?.zh.startsWith(t) == true ||
            builtinTokens[c.name]?.en.toLowerCase().startsWith(lower) == true)
          c,
    ];
  }
}

/// 输入框文本解析：`/` 开头视为斜杠命令草稿。
/// 返回 null = 非命令；否则返回（命令名片段, 已敲的参数部分）。
/// 匹配 bridge 命令名正则 `/^\/([a-z][a-z0-9_-]*)/`。
({String nameFragment, String args})? parseSlashDraft(String text) {
  if (!text.startsWith('/')) return null;
  final m = RegExp(r'^/([a-z][a-z0-9_-]*)(\s+(.*))?$').firstMatch(text);
  if (m == null) {
    // 只有 `/` 或非法片段（如 `/中文`）：给全量清单，参数为空。
    return (nameFragment: text.substring(1), args: '');
  }
  return (nameFragment: m.group(1) ?? '', args: m.group(3) ?? '');
}

/// 输入框 @ 文件引用解析（第六轮反馈 m03878）：光标前最近的 `@路径片段`。
/// 返回 null = 当前没有 @ 草稿；否则返回（查询片段, 替换区间 start/end——
/// 含 @，替换时整段换成补全结果）。@ 后到光标之间不允许出现空白（出现即
/// 视为上一个引用已结束）。
({String query, int start, int end})? parseAtMentionDraft(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  final head = text.substring(0, cursor);
  final at = head.lastIndexOf('@');
  if (at < 0) return null;
  final fragment = head.substring(at + 1);
  // @ 紧贴非路径字符（如 `a@b` 中间无空白也允许）——但 @ 前若是词字符则
  // 多半是邮箱/普通文本，保守不触发，避免误弹面板。
  if (at > 0 && !_atBoundary(head, at)) return null;
  if (fragment.contains(RegExp(r'[\s]'))) return null;
  return (query: fragment, start: at, end: cursor);
}

/// @ 触发边界：@ 前必须是行首或空白/常用开括号，避免邮箱误触。
bool _atBoundary(String head, int at) {
  final prev = head[at - 1];
  return prev == ' ' || prev == '\n' || prev == '\t' || '（(【[「'.contains(prev);
}
