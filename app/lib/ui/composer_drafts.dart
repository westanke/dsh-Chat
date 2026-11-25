/// 输入条草稿按会话保存（对照 chat-demo 的 drafts.ts）。
///
/// chat-demo 的草稿是 `Map<sessionId|null, Draft{text, attachments}>`：
/// 键是会话号，null = 尚未建会话的新对话；切会话时各自保留、发送成功后清掉、
/// 只存本页内存不落盘。这里同口径：键直接用 sessionId（null 即新对话），
/// 草稿只存内存，不写任何持久化存储。
///
/// 与 chat-demo 的差异：chat-demo 的 attachments 带上传状态机，本端选图
/// 即读成 base64（[ComposerDraftImage]），草稿里原样保留，切回会话直接复现。
library;

/// 草稿里的待发送图片：与 Composer 内部 `_PendingImage` 同构，
/// 跨文件共享这个 typedef 避免两处各写一份字段名漂移。
typedef ComposerDraftImage = ({
  String path,
  String name,
  String mediaType,
  String base64,
});

/// 单个会话的输入草稿：输入文字 + 待发送图片。
/// 草稿是可变对象（chat-demo 的 Draft 直接 mutate，切会话时整体覆盖）。
class ComposerDraft {
  ComposerDraft({this.text = '', this.images = const []});

  String text;
  List<ComposerDraftImage> images;

  bool get isEmpty => text.trim().isEmpty && images.isEmpty;
}

/// 按会话保存的输入草稿集合（内存态，键 null = 新对话）。
///
/// 纯逻辑、不碰 Flutter：写在独立文件里好单测，也方便将来任何需要
/// 「输入条状态按会话隔离」的地方复用。
class ComposerDraftStore {
  final Map<String?, ComposerDraft> _drafts = <String?, ComposerDraft>{};

  /// 取 [sessionId] 的草稿；没有则返回空草稿并登记（与 chat-demo
  /// `getDraft` 的 putIfAbsent 口径一致）。返回的是内部对象本身，
  /// 调用方改字段即改草稿（对应 chat-demo 直接 mutate Draft）。
  ComposerDraft draftOf(String? sessionId) =>
      _drafts.putIfAbsent(sessionId, () => ComposerDraft());

  /// 整体保存文字（切会话时由 Composer 调用，覆盖旧值）。
  void setDraftText(String? sessionId, String text) {
    final d = draftOf(sessionId);
    d.text = text;
  }

  /// 整体保存待发送图片列表（覆盖旧值，避免切来切去重复追加）。
  void setDraftImages(String? sessionId, List<ComposerDraftImage> images) {
    final d = draftOf(sessionId);
    d.images = List<ComposerDraftImage>.of(images);
  }

  /// 发送成功后清掉该会话草稿（chat-demo clearSentDraft 口径）。
  void clearSentDraft(String? sessionId) {
    _drafts.remove(sessionId);
  }

  /// 清掉全部草稿（chat-demo clearAllDrafts 口径；测试隔离与「退出登录
  /// 换账号」这类场景用）。
  void clearAllDrafts() => _drafts.clear();

  /// 清掉某个会话的草稿（会话被归档/删除后调用，避免草稿留在内存里）。
  void clearDraft(String? sessionId) {
    _drafts.remove(sessionId);
  }
}

/// 全局唯一草稿表（内存态）：Composer 切会话时读写。
/// 存活期与应用一致，比 chat-demo 的「本页内存」略长，语义上仍是草稿。
final ComposerDraftStore composerDrafts = ComposerDraftStore();
