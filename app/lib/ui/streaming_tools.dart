/// 工具调用实时事件缓冲（桥 fdb85da 起：chat.message.delta kind='tool-call'/
/// 'tool-call-end'、chat.tool.call、chat.tool.result 四种帧的客户端聚合）。
///
/// 数据流：参数流式生成（preparing）→ 参数定稿 → chat.tool.call（running）→
/// chat.tool.result（结果 / error.code 分类）。行按 callId 去重覆盖，后到帧
/// 覆盖前态；缺 callId 的帧按 index 兜底（首包带 id 后迁移 key）。committed
/// 后 reloadHistory 用持久化过程组覆盖本缓冲（_clearStream 清空）。
library;

import '../bridge/models.dart';

/// 单个流式工具行（mutable，仅缓冲内部使用）。
class _StreamingToolRow {
  _StreamingToolRow({required this.key});

  /// 缓冲 key：callId 非空用 callId，否则 'idx'+index。
  final String key;
  String callId = '';
  String name = '';
  String argsRaw = '';
  bool settled = false; // tool-call-end 已定稿参数
  bool running = false; // chat.tool.call 已到
  bool done = false; // chat.tool.result 已到
  bool failed = false;
  String? resultText;
  String? errorCode;
}

/// 聚合器：ChatState 持有一个实例，按事件流顺序喂数据。
class StreamingToolBuffer {
  final Map<String, _StreamingToolRow> _rows = <String, _StreamingToolRow>{};

  /// index → callId（续包只带 index，靠它找回迁移后的行）。
  final Map<int, String> _indexToCallId = <int, String>{};

  bool get isEmpty => _rows.isEmpty;

  /// 按 callId/index 找（或建）行；callId 首次出现时迁移 idx 占位行。
  _StreamingToolRow _rowFor(String? callId, int index) {
    if (callId != null && callId.isNotEmpty) {
      _indexToCallId[index] = callId;
      final stale = _rows.remove('idx$index');
      if (stale != null && stale.callId.isEmpty) {
        stale.callId = callId;
        return _rows.putIfAbsent(callId, () => stale);
      }
      return _rows.putIfAbsent(
        callId,
        () => _StreamingToolRow(key: callId)..callId = callId,
      );
    }
    final mapped = _indexToCallId[index];
    if (mapped != null) {
      return _rows.putIfAbsent(mapped, () => _StreamingToolRow(key: mapped));
    }
    return _rows.putIfAbsent(
      'idx$index',
      () => _StreamingToolRow(key: 'idx$index'),
    );
  }

  /// 参数流式生成（preparing）：增量拼 argsRaw；续包无 id 靠 index 续行。
  void handleDelta(MessageDelta d) {
    final row = _rowFor(d.callId, d.index);
    if (d.name != null) row.name = d.name!;
    final delta = d.argumentsDelta;
    if (delta != null && delta.isNotEmpty) row.argsRaw += delta;
  }

  /// 参数定稿（tool-call-end）：arguments 覆盖累积增量。
  void handleEnd(MessageDelta d) {
    final row = _rowFor(d.callId, d.index);
    if (d.name != null) row.name = d.name!;
    final args = d.arguments;
    if (args != null && args.isNotEmpty) row.argsRaw = args;
    row.settled = true;
  }

  /// 按 callId 找（或建）行——tool/call、tool/result 结构化帧必带 callId
  /// （内核事件），delta 流式块才可能缺 id（rawChunk.id 空时桥不带 callId）。
  _StreamingToolRow _rowByCallId(String callId) => _rows.putIfAbsent(
    callId,
    () => _StreamingToolRow(key: callId)..callId = callId,
  );

  /// 工具开始执行（参数已定稿，覆盖 preparing 行）。
  void handleCall(ToolCallStarted c) {
    if (c.callId.isEmpty) return; // 无 callId 无法对应行，忽略（见 _rowByCallId）
    final row = _rowByCallId(c.callId);
    if (c.name.isNotEmpty) row.name = c.name;
    final args = c.arguments;
    if (args != null && args.isNotEmpty) row.argsRaw = args;
    row
      ..settled = true
      ..running = true;
  }

  /// 工具结果：error.code 分派——'interrupted'=已停止（不算失败）、
  /// ask 的 'ASK_CANCELLED'=已取消（不算失败），其余（含未知值）失败。
  void handleResult(ToolCallOutcome r) {
    if (r.callId.isEmpty) return;
    final row = _rowByCallId(r.callId);
    final text = r.resultText;
    row
      ..resultText = text.isEmpty ? null : text
      ..errorCode = r.errorCode
      ..done = true
      ..running = false
      ..failed =
          r.isError ||
          (r.errorCode != null &&
              r.errorCode != 'interrupted' &&
              r.errorCode != 'ASK_CANCELLED');
  }

  /// 当前缓冲行的展示形态（插入序 = 出现序；缺 name 兜底「工具调用」）。
  List<ToolCallInfo> get infos => [
    for (final row in _rows.values)
      ToolCallInfo(
        callId: row.callId.isEmpty ? row.key : row.callId,
        name: row.name.isEmpty ? '工具调用' : row.name,
        phrases: const [],
        failed: row.failed,
        resultText: row.resultText,
        rawArguments: row.argsRaw.isEmpty ? null : row.argsRaw,
        preparing: !row.settled && !row.running && !row.done,
        errorCode: row.errorCode,
      ),
  ];

  /// 合成过程组（role='process'，seq=-2 表示未 committed 的流式组）；
  /// 空缓冲回 null——列表装配层据此决定是否插入流式过程组。
  ChatMessage? get processMessage => _rows.isEmpty
      ? null
      : ChatMessage(role: 'process', text: '', toolCalls: infos, seq: -2);

  /// 删除已持久化到 history 的工具行（callId 命中），并清掉指向这些行的
  /// index 映射——reloadHistory 的持久过程组已包含这些工具，避免同一
  /// callId「流式行 + 持久组」双份渲染。未命中的行与占位行保留。
  void dropPersisted(Set<String> callIds) {
    if (callIds.isEmpty) return;
    _rows.removeWhere(
      (key, row) => row.callId.isNotEmpty && callIds.contains(row.callId),
    );
    _indexToCallId.removeWhere((index, callId) => callIds.contains(callId));
  }

  void clear() {
    _rows.clear();
    _indexToCallId.clear();
  }
}
