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

/// 斜杠命令（真机反馈 2026-11-04 第 3 项）。
/// bridge `commands` 帧应答 data.commands：`{name, description, input?}`；
/// name 已含前导斜杠还是裸名——ws-commands.ts 的 listCommands 直接透传内核
/// ChatCommandDescriptor，companion 里命令面板按裸名展示、发送时拼 `/`。
/// （listCommands 在会话激活不了时回 []，不报错——chat-adapter.ts:1190-1200。）
class SlashCommand {
  const SlashCommand({
    required this.name,
    required this.description,
    this.inputHint,
  });

  final String name; // 裸名，如 'model'
  final String description;
  final String? inputHint; // 需要参数时的提示

  factory SlashCommand.from(Map<String, dynamic> j) => SlashCommand(
    name: ((j['name'] ?? '') as String).replaceAll(RegExp(r'^/'), ''),
    description: (j['description'] ?? '') as String,
    inputHint: j['input'] is String ? j['input'] as String : null,
  );

  /// 输入框里从 `/abc` 过滤本命令：前缀匹配。
  bool matchesQuery(String q) =>
      q.isEmpty || name.toLowerCase().startsWith(q.toLowerCase());
}

/// `commands` 帧应答收敛。
class SlashCommandList {
  const SlashCommandList({required this.commands});

  final List<SlashCommand> commands;

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
    return SlashCommandList(commands: list);
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
