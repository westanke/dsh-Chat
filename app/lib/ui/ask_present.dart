/// ask_user_question 工具行展示纯函数（官方 AskQuestionRow 状态机移植）。
///
/// 从 tool_present.dart 拆出（单文件 ≤500 行纪律）：问题规格解析
///（args.questions）、结果解析（resultText JSON 的 pending/answers）与
/// 折叠行状态摘要（等待中/已继续/已关闭/已回答计数/已取消）。
library;

import '../bridge/models.dart';
import '../bridge/questions.dart';
import 'tool_present.dart';

/// 一条已提交的 ask 答案（resultText JSON answers 数组的元素）。
class AskAnswerEntry {
  const AskAnswerEntry({
    required this.id,
    this.selected = const [],
    this.custom,
  });

  final String id;
  final List<String> selected;
  final String? custom;

  /// selected 非空或 custom 非空即算已回答（官方 answered 口径）。
  bool get answered =>
      selected.isNotEmpty || (custom != null && custom!.trim().isNotEmpty);
}

/// ask 工具 resultText 的解析形态：pending 标记与 answers 数组（可有皆无）。
class AskResult {
  const AskResult({required this.pending, this.answers});

  final bool pending;
  final List<AskAnswerEntry>? answers;
}

/// 解析 ask 工具 resultText；不是 JSON 对象、且既无 pending 也无 answers →
/// null（调用方回退通用摘要）。
AskResult? askResultOf(String? resultText) {
  final parsed = tryParseJson(resultText);
  if (parsed is! Map) return null;
  final pending = parsed['pending'] == true;
  final rawAnswers = parsed['answers'];
  List<AskAnswerEntry>? answers;
  if (rawAnswers is List) {
    final entries = <AskAnswerEntry>[];
    for (final item in rawAnswers) {
      if (item is! Map) continue;
      final id = item['id'];
      if (id is! String || id.isEmpty) continue;
      final selected = <String>[];
      final rawSelected = item['selected'];
      if (rawSelected is List) {
        for (final s in rawSelected) {
          if (s is String && s.isNotEmpty) selected.add(s);
        }
      }
      entries.add(
        AskAnswerEntry(
          id: id,
          selected: selected,
          custom: item['custom'] is String ? item['custom'] as String : null,
        ),
      );
    }
    answers = entries;
  }
  if (!pending && answers == null) return null;
  return AskResult(pending: pending, answers: answers);
}

/// 解析 ask 工具 args.questions（官方 AskQuestionSpec）：重复 id / 缺
/// id 或 question / 空列表 / 坏 JSON → null（调用方回退通用详情）。
List<UserQuestion>? askQuestions(String? rawArguments) {
  final parsed = tryParseJson(rawArguments);
  if (parsed is! Map) return null;
  final rawQuestions = parsed['questions'];
  if (rawQuestions is! List || rawQuestions.isEmpty) return null;
  final seen = <String>{};
  final out = <UserQuestion>[];
  for (final item in rawQuestions) {
    if (item is! Map) return null;
    final id = item['id'];
    final question = item['question'];
    if (id is! String || id.isEmpty) return null;
    if (question is! String || question.isEmpty) return null;
    if (!seen.add(id)) return null;
    out.add(
      UserQuestion(
        id: id,
        question: question,
        header: item['header'] is String ? item['header'] as String : null,
        detail: item['detail'] is String ? item['detail'] as String : null,
        // args 用官方 snake_case multi_select；兼容驼峰键。
        multiSelect:
            item['multi_select'] == true || item['multiSelect'] == true,
        options: UserQuestionOption.listFrom(item['options']),
      ),
    );
  }
  return out;
}

/// ask_user_question 工具行的状态摘要（官方 AskQuestionRow 状态机）：
/// - running 且无结果 →「等待中」；
/// - resultText pending 且 HITL 挂起表还有该 callId（[answerable]）→
///   「已继续；仍可回答」，否则「已关闭」；
/// - answers 数组 →「{answered}/{total} 已回答」（answered = selected 或
///   custom 非空计数）；
/// - 解析失败 → 原参数摘要兜底。
String? askSummary(ToolCallInfo call, bool Function(String callId) answerable) {
  if (isCallRunning(call)) return '等待中';
  // 工具结果 error.code='ASK_CANCELLED' →「已取消」（官方 ask.cancelled；
  // TOOL_OUTCOME_UNKNOWN 等其余分类走失败态，不进这里）。
  if (call.errorCode == 'ASK_CANCELLED') return '已取消';
  final result = askResultOf(call.resultText);
  if (result != null) {
    if (result.pending) {
      return answerable(call.callId) ? '已继续；仍可回答' : '已关闭';
    }
    final answers = result.answers;
    if (answers != null) {
      // 官方 answeredPresentation 的 total 用答案批次数（answers.length）。
      final answered = answers.where((a) => a.answered).length;
      return '$answered/${answers.length} 已回答';
    }
  }
  return call.summary;
}
