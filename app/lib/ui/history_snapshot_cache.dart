/// 会话历史的短暂缓存（从 chat_state/history_actions 共用的小模块）。
///
/// ## 解决什么问题
///
/// 打开大会话时 `openSession()` 会先清空 messages 再等一次 `history` 往返
/// （首屏 80 条 + projections，真机上常是 1–4 秒）。用户从抽屉点一个之前看过
/// 的会话，看到的是整页 loading，哪怕内容刚刚才在他手机上。
///
/// 这里只缓存**最近看过的几个会话的最后一屏**（默认 4 个、10 分钟），
/// 打开时先上屏再后台刷新（stale-while-revalidate）。不持久化到磁盘：
/// 历史会随新消息/归档变化，跨进程复用会把陈旧内容当真。
library;

import '../bridge/history_page.dart';

/// 一个会话的最后一屏快照。
class HistorySnapshot {
  const HistorySnapshot({
    required this.messages,
    required this.rawEvents,
    required this.hasMore,
    required this.truncated,
    required this.projections,
    required this.capturedAt,
  });

  final List<ChatMessage> messages;
  final List<Map<String, dynamic>> rawEvents;
  final bool hasMore;
  final bool truncated;
  final Map<String, dynamic>? projections;
  final DateTime capturedAt;

  bool isFresh(Duration maxAge) =>
      DateTime.now().difference(capturedAt) <= maxAge;
}

/// 进程内 LRU 快照缓存（单例；会话 id 作键）。
class HistorySnapshotCache {
  HistorySnapshotCache();

  /// 进程内共享实例（应用里只有这一份缓存；测试可自建独立实例）。
  static final HistorySnapshotCache instance = HistorySnapshotCache();

  /// 同时保留的会话数：4 个足够覆盖「抽屉里来回切两三个」的路径。
  static const int maxEntries = 4;

  /// 默认有效期：10 分钟。超过就当没有，避免长期陈旧。
  static const Duration maxAge = Duration(minutes: 10);

  final Map<String, HistorySnapshot> _byId = {};

  /// 读：命中且未过期才返回；过期条目顺手丢掉。
  HistorySnapshot? take(String sessionId) {
    final snap = _byId[sessionId];
    if (snap == null) return null;
    if (!snap.isFresh(maxAge)) {
      _byId.remove(sessionId);
      return null;
    }
    return snap;
  }

  /// 写：刷新 LRU 位置，超容量时丢最旧的一条。
  void put(String sessionId, HistorySnapshot snapshot) {
    _byId.remove(sessionId);
    _byId[sessionId] = snapshot;
    while (_byId.length > maxEntries) {
      _byId.remove(_byId.keys.first);
    }
  }

  void drop(String sessionId) => _byId.remove(sessionId);

  void clear() => _byId.clear();
}
