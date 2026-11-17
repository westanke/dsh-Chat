/// tool_present.dart 纯函数单测（官方 Web 工具调用展示语义逐条对照）：
/// activityKind/toolTitle/summarizeArgs/liveDetailText/reasoningDetailOf/
/// processGroupTitle（两词并接去「已」/三类逗号/超三类加「等」/空组兜底）/
/// askSummary/askQuestions/askResultOf（坏 JSON 兜底、多题计数、skipped 计数）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dshchat/bridge/models.dart';
import 'package:dshchat/ui/ask_present.dart';
import 'package:dshchat/ui/tool_present.dart';
import 'package:dshchat/ui/tool_titles.dart';

ToolCallInfo callOf(
  String name, {
  String callId = 'c1',
  String? summary,
  String? rawArguments,
  String? resultText,
  bool failed = false,
  int? durationMs,
  bool preparing = false,
  String? errorCode,
}) {
  return ToolCallInfo(
    callId: callId,
    name: name,
    phrases: const ['工具'],
    summary: summary,
    rawArguments: rawArguments,
    resultText: resultText,
    failed: failed,
    durationMs: durationMs,
    preparing: preparing,
    errorCode: errorCode,
  );
}

ChatMessage groupOf(List<ToolCallInfo> calls) =>
    ChatMessage(role: 'process', text: '', toolCalls: calls);

void main() {
  group('activityKind', () {
    test('官方词表映射', () {
      expect(activityKind('read'), ToolActivityKind.read);
      expect(activityKind('tools.read'), ToolActivityKind.read);
      expect(activityKind('read_image'), ToolActivityKind.readImage);
      expect(activityKind('grep'), ToolActivityKind.search);
      expect(activityKind('tools.glob'), ToolActivityKind.search);
      expect(activityKind('repo_inspect'), ToolActivityKind.search);
      expect(activityKind('write'), ToolActivityKind.write);
      expect(activityKind('edit'), ToolActivityKind.edit);
      expect(activityKind('apply_patch'), ToolActivityKind.edit);
      expect(activityKind('bash'), ToolActivityKind.commands);
      expect(activityKind('pwsh'), ToolActivityKind.commands);
      expect(activityKind('exec_command'), ToolActivityKind.commands);
      expect(activityKind('write_stdin'), ToolActivityKind.commands);
      expect(activityKind('terminal_run'), ToolActivityKind.commands);
      expect(activityKind('run_code'), ToolActivityKind.code);
      expect(activityKind('web_search'), ToolActivityKind.webSearch);
      expect(activityKind('web_fetch'), ToolActivityKind.webFetch);
      expect(activityKind('subagent'), ToolActivityKind.subagents);
      expect(activityKind('subagent_spawn'), ToolActivityKind.subagents);
      expect(activityKind('ask_user_question'), ToolActivityKind.questions);
      expect(activityKind('todo_write'), ToolActivityKind.plan);
      expect(activityKind('mcp__docs__search'), ToolActivityKind.tools);
      expect(activityKind('unknown_tool'), ToolActivityKind.tools);
      expect(activityKind(''), ToolActivityKind.thinking);
    });
  });

  group('toolTitle', () {
    test('官方 TOOL_TITLE_KEYS 精确名优先，其次变体词表', () {
      expect(toolTitle('pwsh'), '运行命令');
      expect(toolTitle('grep'), '搜索文件内容');
      expect(toolTitle('glob'), '查找文件');
      expect(toolTitle('web_search'), '网页搜索');
      expect(toolTitle('web_fetch'), '网页获取');
      expect(toolTitle('bash'), '运行命令');
      expect(toolTitle('tools.read'), '读取');
      expect(toolTitle('read_image'), '读取图片');
      expect(toolTitle('ask_user_question'), '提问');
      expect(toolTitle('todo_write'), '更新任务清单');
      expect(toolTitle('lsp'), '查询代码符号');
      expect(toolTitle('mcp__x__y'), '工具调用');
      expect(isGenericTool('mcp__x__y'), isTrue);
      expect(isGenericTool('grep'), isFalse);
    });
  });

  group('summarizeArgs', () {
    test('commands：description 优先于 command', () {
      expect(
        summarizeArgs(
          ToolActivityKind.commands,
          '{"description":"打包","command":"ls -la"}',
        ),
        '打包',
      );
      expect(
        summarizeArgs(ToolActivityKind.commands, '{"command":"ls -la"}'),
        'ls -la',
      );
    });

    test('read：path / file_path / url 键序', () {
      expect(
        summarizeArgs(ToolActivityKind.read, '{"file_path":"/a/b"}'),
        '/a/b',
      );
      expect(summarizeArgs(ToolActivityKind.read, '{"path":"/a"}'), '/a');
    });

    test('search：queries 数组 join，query 兜底', () {
      expect(
        summarizeArgs(
          ToolActivityKind.search,
          '{"queries":["web socket","http"]}',
        ),
        'web socket, http',
      );
      expect(summarizeArgs(ToolActivityKind.search, '{"query":"多\\n行"}'), '多');
    });

    test('write/edit：path 键', () {
      expect(
        summarizeArgs(ToolActivityKind.edit, '{"file_path":"a.dart"}'),
        'a.dart',
      );
    });

    test('未知 kind → 首个字符串值首行', () {
      expect(
        summarizeArgs(ToolActivityKind.tools, '{"name":"mcp","x":1,"y":"z"}'),
        'mcp',
      );
    });

    test('坏 JSON → 原文首行兜底', () {
      expect(summarizeArgs(ToolActivityKind.read, '不是json'), '不是json');
      expect(summarizeArgs(ToolActivityKind.read, null), isNull);
    });
  });

  group('liveDetailText / reasoningDetailOf', () {
    test('取运行中调用的 detail 键值', () {
      final g = groupOf([
        callOf('bash', callId: 'a', rawArguments: '{"description":"编译"}'),
        callOf('read', callId: 'b', rawArguments: '{"file_path":"/x/y"}'),
      ]);
      expect(liveDetailText(g), '/x/y');
    });

    test('queries 数组取首项首行；超长截断', () {
      final g = groupOf([
        callOf('grep', callId: 'a', rawArguments: '{"queries":["foo\\nbar"]}'),
      ]);
      expect(liveDetailText(g), 'foo');
      final long = '长' * 200;
      final g2 = groupOf([
        callOf('bash', callId: 'a', rawArguments: '{"command":"$long"}'),
      ]);
      // clipText：160 字符 + 省略号。
      final detail = liveDetailText(g2)!;
      expect(detail.length, 161);
      expect(detail.endsWith('…'), isTrue);
    });

    test('无运行中调用 → null；reasoningDetailOf 取最后一段非空', () {
      expect(liveDetailText(groupOf([])), isNull);
      expect(reasoningDetailOf('第一段\n\n第二段'), '第二段');
      expect(reasoningDetailOf('带**强调**'), '带强调');
      expect(reasoningDetailOf(null), isNull);
    });
  });

  group('processGroupTitle', () {
    test('空组兜底「已完成分析」', () {
      expect(processGroupTitle(groupOf([]), liveDetail: true), '已完成分析');
    });

    test('运行中 + liveDetail 后缀；关 detail 则无后缀', () {
      final g = groupOf([
        callOf('bash', rawArguments: '{"description":"编译中"}'),
      ]);
      expect(processGroupTitle(g, liveDetail: true), '正在运行命令 · 编译中');
      expect(processGroupTitle(g, liveDetail: false), '正在运行命令');
    });

    test('preparing（rawArguments null）→ 准备运行命令', () {
      final g = groupOf([callOf('bash')]);
      expect(processGroupTitle(g, liveDetail: true), '准备运行命令');
    });

    test('reasoningHint 兜底（无 detail 键值时）', () {
      final g = groupOf([callOf('read', rawArguments: '{}')]);
      expect(
        processGroupTitle(g, liveDetail: true, reasoningHint: '正在找配置'),
        '正在读取文件 · 正在找配置',
      );
    });

    test('完成：两类「并」接且去「已」', () {
      final g = groupOf([
        callOf('read', callId: 'a', resultText: 'x'),
        callOf('bash', callId: 'b', resultText: 'y'),
      ]);
      expect(processGroupTitle(g, liveDetail: true), '已读取文件并执行了命令');
    });

    test('完成：三类逗号连接；四类加「等」', () {
      final g3 = groupOf([
        callOf('read', callId: 'a', resultText: 'x'),
        callOf('bash', callId: 'b', resultText: 'y'),
        callOf('grep', callId: 'c', resultText: 'z'),
      ]);
      expect(processGroupTitle(g3, liveDetail: false), '已读取文件，执行了命令，已搜索代码');
      final g4 = groupOf([
        callOf('read', callId: 'a', resultText: 'x'),
        callOf('bash', callId: 'b', resultText: 'y'),
        callOf('grep', callId: 'c', resultText: 'z'),
        callOf('write', callId: 'd', resultText: 'w'),
      ]);
      final title = processGroupTitle(g4, liveDetail: false);
      expect(title.endsWith('等'), isTrue);
    });

    test('完成：按计数排序取前三类', () {
      final g = groupOf([
        callOf('bash', callId: 'a', resultText: 'x'),
        callOf('bash', callId: 'a2', resultText: 'x'),
        callOf('bash', callId: 'a3', resultText: 'x'),
        callOf('read', callId: 'b', resultText: 'y'),
        callOf('read', callId: 'b2', resultText: 'y'),
        callOf('grep', callId: 'c', resultText: 'z'),
        callOf('write', callId: 'd', resultText: 'w'),
      ]);
      expect(processGroupTitle(g, liveDetail: false), '执行了命令，已读取文件，已搜索代码等');
    });
  });

  group('askResultOf / askQuestions', () {
    test('pending 与 answers 均可解析；坏 JSON → null', () {
      final p = askResultOf('{"pending":true}');
      expect(p, isNotNull);
      expect(p!.pending, isTrue);
      expect(p.answers, isNull);
      final a = askResultOf(
        '{"answers":[{"id":"q1","selected":["A"]},{"id":"q2","custom":"自答"}]}',
      );
      expect(a!.answers, isNotNull);
      expect(a.answers![1].answered, isTrue);
      expect(askResultOf('不是json'), isNull);
      expect(askResultOf('{"other":1}'), isNull);
    });

    test('askQuestions：合法/重复 id/缺字段/空列表', () {
      final qs = askQuestions(
        '{"questions":[{"id":"q1","question":"选哪个","multi_select":true,'
        '"options":[{"label":"A"},{"label":"B"}]},'
        '{"id":"q2","question":"自由输入"}]}',
      );
      expect(qs, isNotNull);
      expect(qs!.length, 2);
      expect(qs[0].multiSelect, isTrue);
      expect(
        askQuestions(
          '{"questions":[{"id":"q1","question":"重复"},'
          '{"id":"q1","question":"重复"}]}',
        ),
        isNull,
      );
      expect(askQuestions('{"questions":[{"id":"q1"}]}'), isNull);
      expect(askQuestions('{"questions":[]}'), isNull);
      expect(askQuestions('不是json'), isNull);
    });
  });

  group('askSummary', () {
    test('running → 等待回答', () {
      expect(askSummary(callOf('ask_user_question'), (_) => false), '等待回答');
    });

    test('pending：answerable 决定已继续工作，仍可回答/已结束', () {
      final pending = callOf(
        'ask_user_question',
        resultText: '{"pending":true}',
      );
      expect(askSummary(pending, (_) => true), '已继续工作，仍可回答');
      expect(askSummary(pending, (_) => false), '已结束');
    });

    test('answers 计数：skipped 不计入，total 取题数', () {
      final answered = callOf(
        'ask_user_question',
        summary: '原摘要',
        rawArguments: '{"questions":[{"id":"q1","question":"一"},{"id":"q2","question":"二"}]}',
        resultText: '{"answers":[{"id":"q1","selected":["A"]},{"id":"q2"}]}',
      );
      expect(askSummary(answered, (_) => false), '1/2 已回答');
    });

    test('解析失败 → 原 summary 兜底', () {
      final fallback = callOf(
        'ask_user_question',
        summary: '原摘要',
        resultText: '纯文本结果',
      );
      expect(askSummary(fallback, (_) => false), '原摘要');
    });

    test('ASK_CANCELLED →「已取消」（ask 卡取消态）', () {
      final cancelled = callOf(
        'ask_user_question',
        resultText: 'pending true', // 不影响：errorCode 优先于结果解析
        errorCode: 'ASK_CANCELLED',
      );
      expect(askSummary(cancelled, (_) => false), '已取消');
    });
  });

  group('toolRowStateOf / isToolRowLive', () {
    test(
      'errorCode 终态分派：interrupted→stopped、ask 的 ASK_CANCELLED→cancelled',
      () {
        expect(
          toolRowStateOf(callOf('tools.bash', errorCode: 'interrupted')),
          ToolRowState.stopped,
        );
        expect(
          toolRowStateOf(
            callOf('ask_user_question', errorCode: 'ASK_CANCELLED'),
          ),
          ToolRowState.cancelled,
        );
        // 非 ask 工具带 ASK_CANCELLED → 防御性失败态。
        expect(
          toolRowStateOf(callOf('tools.bash', errorCode: 'ASK_CANCELLED')),
          ToolRowState.failed,
        );
      },
    );

    test('TOOL_OUTCOME_UNKNOWN / 未知 code / isError → failed', () {
      expect(
        toolRowStateOf(callOf('tools.bash', errorCode: 'TOOL_OUTCOME_UNKNOWN')),
        ToolRowState.failed,
      );
      expect(
        toolRowStateOf(callOf('tools.bash', errorCode: 'SOMETHING_ELSE')),
        ToolRowState.failed,
      );
      expect(
        toolRowStateOf(callOf('tools.bash', resultText: 'boom', failed: true)),
        ToolRowState.failed,
      );
    });

    test('ok / preparing（真标记与 rawArguments==null 近似）/ running', () {
      expect(
        toolRowStateOf(callOf('tools.bash', resultText: 'done')),
        ToolRowState.ok,
      );
      expect(
        toolRowStateOf(
          callOf('tools.bash', rawArguments: '{"comm', preparing: true),
        ),
        ToolRowState.preparing,
      );
      expect(
        toolRowStateOf(callOf('tools.bash', rawArguments: null)),
        ToolRowState.preparing,
      );
      expect(
        toolRowStateOf(callOf('tools.bash', rawArguments: '{"command": "ls"}')),
        ToolRowState.running,
      );
    });

    test('isToolRowLive：preparing 与 running 算活行；终态不算', () {
      expect(isToolRowLive(callOf('tools.bash', rawArguments: null)), isTrue);
      expect(
        isToolRowLive(callOf('tools.bash', rawArguments: '{"command": "ls"}')),
        isTrue,
      );
      expect(isToolRowLive(callOf('tools.bash', resultText: 'done')), isFalse);
      expect(
        isToolRowLive(callOf('tools.bash', errorCode: 'interrupted')),
        isFalse,
      );
    });
  });

  group('parseExitStatus / 徽标', () {
    test('尾部 [exit code: N] / [killed by signal: X] 解析', () {
      final ok = parseExitStatus('ls 输出\n[exit code: 0]');
      expect(ok!.exitCode, 0);
      final bad = parseExitStatus('boom\n[exit code: 2]');
      expect(bad!.exitCode, 2);
      final killed = parseExitStatus('out\n[killed by signal: SIGKILL]');
      expect(killed!.signal, 'SIGKILL');
      expect(killed.exitCode, isNull);
      final noExit = parseExitStatus('[exit code: null]');
      expect(noExit!.noExit, isTrue);
      expect(noExit.exitCode, isNull);
      expect(parseExitStatus('没有标记的结果'), isNull);
      expect(parseExitStatus(null), isNull);
    });

    test('徽标文案与颜色语义', () {
      // 官方 terminalExitLabel：信号 →「信号 X」、非 0 →「退出码 N」、
      // exit 0 视为成功不出徽标（terminalFailed 判据）。
      expect(exitBadgeLabel(parseExitStatus('x\n[exit code: 2]')), '退出码 2');
      expect(exitBadgeLabel(parseExitStatus('x\n[exit code: 0]')), isNull);
      expect(exitBadgeLabel(parseExitStatus('x\n[exit code: null]')), '未正常退出');
      expect(
        exitBadgeLabel(parseExitStatus('x\n[killed by signal: SIGTERM]')),
        '信号 SIGTERM',
      );
      expect(exitBadgeIsError(parseExitStatus('x\n[exit code: 2]')), isTrue);
      expect(exitBadgeIsError(parseExitStatus('x\n[exit code: 0]')), isFalse);
      expect(exitBadgeIsError(parseExitStatus('x\n[exit code: null]')), isTrue);
      expect(
        exitBadgeIsError(parseExitStatus('x\n[killed by signal: SIGKILL]')),
        isTrue,
      );
      expect(exitBadgeIsError(parseExitStatus('x')), isFalse);
      expect(exitBadgeIsError(null), isFalse);
    });
  });

  group('processGroupTitle preparing 真数据驱动', () {
    test('preparing 标记行 →「准备…」词（即使 rawArguments 已有增量）', () {
      final title = processGroupTitle(
        groupOf([callOf('tools.read', rawArguments: '{"pat', preparing: true)]),
        liveDetail: true,
      );
      expect(title, '准备读取文件');
    });

    test('rawArguments==null 的 running 行保留 preparing 近似回退', () {
      expect(
        processGroupTitle(groupOf([callOf('tools.write')]), liveDetail: false),
        '准备写入文件',
      );
    });

    test('stopped 行不算活行 → 组标题走完成态聚合', () {
      final title = processGroupTitle(
        groupOf([callOf('tools.bash', errorCode: 'interrupted')]),
        liveDetail: true,
      );
      expect(title, '执行了命令');
    });
  });
}
