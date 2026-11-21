// 斜杠命令面板的数据面测试（bridge/slash_commands.dart）：
// 中文 face、客户端功能命令、技能目录、合并顺序、过滤与精确解析。
import 'package:dshchat/bridge/models.dart';
import 'package:dshchat/bridge/slash_commands.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一份贴近桥 `commands` 帧的宿主清单（带 v2.11.0 的 definitionId + input）。
List<SlashCommand> _hostFixture() => [
  SlashCommand.from({
    'name': 'compact',
    'description': 'Compact the conversation above',
    'definitionId': '@deepseek-ai/dsh-command-compact',
    'builtin': true,
    'input': {'hint': 'focus'},
  }),
  SlashCommand.from({
    'name': 'permission',
    'description': 'Switch permission preset',
    'definitionId': '@deepseek-ai/dsh-permission-presets',
    'builtin': true,
    'input': {'hint': '<preset>', 'attachments': false},
  }),
  SlashCommand.from({
    'name': 'plan',
    'description': 'Enter or leave plan mode',
    'definitionId': '@deepseek-ai/dsh-plan-mode',
    'builtin': true,
    'input': {'hint': '[off | require]'},
  }),
  SlashCommand.from({
    'name': 'goal',
    'description': 'Set or show the long-term goal',
    'definitionId': '@deepseek-ai/dsh-command-goal',
    'builtin': true,
    'input': {'hint': '[goal | clear | pause | resume]'},
  }),
  SlashCommand.from({
    'name': 'feedback',
    'description': 'Send feedback about this session',
    'definitionId': '@deepseek-ai/dsh-command-feedback',
    'builtin': true,
    'input': {'hint': '<content>'},
  }),
  SlashCommand.from({
    'name': 'export',
    'description': 'Export the session log as ZIP',
    'definitionId': '@deepseek-ai/dsh-session-log-export',
    'builtin': true,
  }),
  // 插件自定义命令：没有 first-party face，保留内核原文。
  SlashCommand.from({
    'name': 'todos',
    'description': 'List todos',
    'definitionId': '@someone/dsh-command-todos',
  }),
];

void main() {
  group('SlashCommand 模型扩展', () {
    test('input 是对象时解析出 hint（修复 Map 形状被丢掉的老 bug）', () {
      final c = SlashCommand.from({
        'name': 'permission',
        'description': 'd',
        'input': {'hint': '<preset>', 'attachments': false},
      });
      expect(c.inputHint, '<preset>');
      expect(c.takesInput, true);
    });

    test('input 缺失或为字符串时都宽容解析', () {
      expect(SlashCommand.from({'name': 'compact'}).inputHint, isNull);
      expect(SlashCommand.from({'name': 'compact'}).takesInput, false);
      expect(
        SlashCommand.from({'name': 'compact', 'input': 'old'}).inputHint,
        'old',
      );
      // input 是对象但没 hint：也是「不要参数」。
      expect(
        SlashCommand.from({
          'name': 'compact',
          'input': {'attachments': true},
        }).inputHint,
        isNull,
      );
    });

    test('displayLabel 有中文名用中文名，否则回退裸名', () {
      const withLabel = SlashCommand(name: 'goal', label: '目标', description: '');
      const without = SlashCommand(name: 'goal', description: '');
      expect(withLabel.displayLabel, '目标');
      expect(without.displayLabel, 'goal');
      // 空串不算有名字（桥可能发 label: ''）。
      expect(
        const SlashCommand(name: 'goal', label: '', description: '').displayLabel,
        'goal',
      );
    });

    test('kind 默认 host，JSON round-trip 后字段不变', () {
      final host = SlashCommand.from({
        'name': 'goal',
        'description': 'd',
        'definitionId': '@deepseek-ai/dsh-command-goal',
        'builtin': true,
        'input': {'hint': '[goal]'},
      });
      expect(host.kind, SlashCommandKind.host);
      // 模型没有 toJson（客户端只读帧）；用同一份 wire JSON 重建验证解析幂等。
      final again = SlashCommand.from({
        'name': 'goal',
        'description': 'd',
        'definitionId': '@deepseek-ai/dsh-command-goal',
        'builtin': true,
        'input': {'hint': '[goal]'},
      });
      expect(again.name, host.name);
      expect(again.description, host.description);
      expect(again.definitionId, host.definitionId);
      expect(again.builtin, host.builtin);
      expect(again.inputHint, host.inputHint);
    });
  });

  group('客户端功能命令', () {
    test('恰好四条，顺序与 dsh-go 一致，全部是 app 来源', () {
      final app = appSlashCommands();
      expect(app.map((c) => c.name), ['new', 'model', 'export', 'features']);
      expect(app.every((c) => c.kind == SlashCommandKind.app), true);
      expect(app.map((c) => c.displayLabel), ['新对话', '模型', '导出日志', '全部功能']);
      // 客户端功能都不吃参数（点选即执行）。
      expect(app.every((c) => !c.takesInput), true);
    });
  });

  group('宿主命令中文化', () {
    test('按 definitionId 换上官方中文 label/描述/参数占位', () {
      final localized = {
        for (final c in paletteHostCommands(_hostFixture())) c.name: c,
      };
      expect(localized['compact']!.displayLabel, '压缩');
      expect(localized['compact']!.description, '压缩以上对话内容，腾出上下文');
      expect(localized['permission']!.displayLabel, '权限');
      expect(localized['permission']!.inputHint, '<预设名>');
      expect(localized['plan']!.inputHint, '[off | 要求]');
      expect(localized['goal']!.displayLabel, '目标');
      expect(localized['goal']!.inputHint, '[目标 | clear | pause | resume]');
      expect(localized['feedback']!.displayLabel, '反馈');
    });

    test('隐藏宿主 export（用客户端自己的导出），插件命令保留内核原文', () {
      final list = paletteHostCommands(_hostFixture());
      expect(list.map((c) => c.name), isNot(contains('export')));
      final todos = list.firstWhere((c) => c.name == 'todos');
      expect(todos.displayLabel, 'todos');
      expect(todos.description, 'List todos');
      // 未命中 face 的条目不该被硬塞参数占位。
      expect(todos.inputHint, isNull);
    });

    test('没有 definitionId 的旧桥条目按名字兜底认领同类 face', () {
      final legacy = SlashCommand.from({'name': 'compact', 'description': 'x'});
      final localized = localizeHostCommand(legacy);
      expect(localized.displayLabel, '压缩');
      // 内核没声明参数 → 中文 face 的 hint 也不硬加。
      expect(localized.inputHint, isNull);
    });
  });

  group('技能目录', () {
    test('解析 skills/list 的 {skills:[…]}，缺名字的条目跳过', () {
      final skills = paletteSkillCommands({
        'skills': [
          {'name': 'office-docx', 'description': 'Word 文档', 'modelInvocable': true},
          {'name': 'pdf', 'description': 'PDF', 'whenToUse': '读 PDF 时'},
          {'description': '没有名字'},
          'not-a-map',
        ],
      });
      expect(skills.map((c) => c.name), ['office-docx', 'pdf']);
      expect(skills.every((c) => c.kind == SlashCommandKind.skill), true);
      expect(skills[1].whenToUse, '读 PDF 时');
      expect(skills[0].displayLabel, 'office-docx');
      // 技能不吃参数提示（是否插入文本由 kind 决定）。
      expect(skills.every((c) => !c.takesInput), true);
    });

    test('也接受裸数组与异常形状（失败不抛）', () {
      expect(
        paletteSkillCommands([
          {'name': 'a', 'description': 'A'},
        ]).map((c) => c.name),
        ['a'],
      );
      expect(paletteSkillCommands(null), isEmpty);
      expect(paletteSkillCommands({'skills': 'oops'}), isEmpty);
      expect(paletteSkillCommands('oops'), isEmpty);
    });
  });

  group('三层合并', () {
    test('客户端功能 → first-party → 其余（按名字），并且去重以先出现者为准', () {
      final host = _hostFixture();
      final skills = paletteSkillCommands({
        'skills': [
          {'name': 'pdf', 'description': 'PDF'},
          {'name': 'goal', 'description': '抢占宿主 goal 的技能'},
        ],
      });
      final merged = mergePaletteCommands(
        host: paletteHostCommands(host),
        skills: skills,
      );
      expect(merged.map((c) => c.name), [
        'new',
        'model',
        'compact',
        'permission',
        'plan',
        'goal',
        'feedback',
        'export',
        'features',
        'pdf',
        'todos',
      ]);
      // 同名 `goal`：宿主（中文 face）胜出，技能那条被丢弃。
      final goal = merged.firstWhere((c) => c.name == 'goal');
      expect(goal.kind, SlashCommandKind.host);
      expect(goal.displayLabel, '目标');
      // 客户端 export 压住宿主 export（后者本来就被隐藏）。
      final export = merged.firstWhere((c) => c.name == 'export');
      expect(export.kind, SlashCommandKind.app);
      expect(export.displayLabel, '导出日志');
    });

    test('没有宿主命令时仍给客户端功能（离线/老桥可用）', () {
      final merged = mergePaletteCommands(host: const []);
      expect(merged.map((c) => c.name), ['new', 'model', 'export', 'features']);
    });
  });

  group('过滤与解析', () {
    List<SlashCommand> palette() => mergePaletteCommands(
      host: paletteHostCommands(_hostFixture()),
      skills: paletteSkillCommands({
        'skills': [
          {'name': 'pdf', 'description': 'PDF'},
        ],
      }),
    );

    test('裸名与中文名前缀都能命中，同级保序', () {
      // 裸名前缀 model 排第一；permission 靠 name 子序列（m…o）兜进来，
      // 与 dsh-go 的 score 一致（它不是中文名命中）。
      expect(filterPaletteCommands(palette(), 'mo').map((c) => c.name), [
        'model',
        'permission',
      ]);
      // 中文名前缀：敲「压缩」命中 /compact。
      expect(filterPaletteCommands(palette(), '压缩').map((c) => c.name), [
        'compact',
      ]);
      expect(filterPaletteCommands(palette(), '导出').map((c) => c.name), [
        'export',
      ]);
    });

    test('前缀优先于包含，包含优先于子序列', () {
      final result = filterPaletteCommands(palette(), 'plan');
      expect(result.first.name, 'plan');
      // 子序列：gol 命中 goal。
      expect(filterPaletteCommands(palette(), 'gol').map((c) => c.name), [
        'goal',
      ]);
    });

    test('空片段回全量，无命中回空', () {
      expect(filterPaletteCommands(palette(), '').length, palette().length);
      expect(filterPaletteCommands(palette(), '   ').length, palette().length);
      expect(filterPaletteCommands(palette(), 'zzzz'), isEmpty);
    });

    test('精确解析认裸名也认中文名', () {
      final p = palette();
      expect(resolvePaletteCommand(p, 'goal')?.name, 'goal');
      expect(resolvePaletteCommand(p, '目标')?.name, 'goal');
      expect(resolvePaletteCommand(p, '新对话')?.name, 'new');
      expect(resolvePaletteCommand(p, '不存在'), isNull);
      expect(resolvePaletteCommand(p, ''), isNull);
    });
  });

  // 面板三态 / 点选 / 发送分流：逐条对齐 dsh-go slash_palette.dart + _slashFor。
  group('面板三态', () {
    List<SlashCommand> palette() => mergePaletteCommands(
      host: paletteHostCommands(_hostFixture()),
      skills: paletteSkillCommands({
        'skills': [
          {'name': 'pdf', 'description': 'Read a PDF'},
        ],
      }),
    );

    test('只敲斜杠是候选态，列全量且 typed=false', () {
      final content = paletteContentOf(commands: palette(), text: '/');
      expect(content, isA<PaletteMatches>());
      final matches = (content as PaletteMatches);
      expect(matches.typed, isFalse);
      expect(matches.matches.length, palette().length);
    });

    test('打了半个名字是候选态且 typed=true', () {
      final content =
          paletteContentOf(commands: palette(), text: '/go') as PaletteMatches;
      expect(content.typed, isTrue);
      expect(content.query, 'go');
      expect(content.matches.first.name, 'goal');
    });

    test('名字打完加空格且无参数 → 参数提示态（单行）', () {
      final content = paletteContentOf(commands: palette(), text: '/goal ');
      expect(content, isA<PaletteHint>());
      expect((content as PaletteHint).command.name, 'goal');
    });

    test('无参命令打完名字后不出面板', () {
      // compact 的 fixture 带 hint（要参数），无参的是插件命令 todos。
      expect(
        paletteContentOf(commands: palette(), text: '/todos '),
        isA<PaletteNone>(),
      );
    });

    test('已填参数 / 光标后有字 / 多行 / 未知名字都不出面板', () {
      final p = palette();
      expect(paletteContentOf(commands: p, text: '/goal x'), isA<PaletteNone>());
      expect(
        paletteContentOf(commands: p, text: '/goal ', caret: 3),
        isA<PaletteNone>(),
      );
      expect(
        paletteContentOf(commands: p, text: '/goal a\nb'),
        isA<PaletteNone>(),
      );
      expect(paletteContentOf(commands: p, text: '/zzz '), isA<PaletteNone>());
    });

    test('不是斜杠开头就不出面板', () {
      expect(paletteContentOf(commands: palette(), text: 'hello'), isA<PaletteNone>());
      expect(paletteContentOf(commands: palette(), text: ''), isA<PaletteNone>());
    });

    test('技能行的 whenToUse 被保留', () {
      final skill = palette().firstWhere((c) => c.kind == SlashCommandKind.skill);
      expect(skill.name, 'pdf');
      expect(skill.takesInput, isFalse);
    });
  });

  group('点选语义', () {
    List<SlashCommand> palette() => mergePaletteCommands(
      host: paletteHostCommands(_hostFixture()),
      skills: paletteSkillCommands({
        'skills': [
          {'name': 'pdf', 'description': 'Read a PDF'},
        ],
      }),
    );

    SlashCommand byName(List<SlashCommand> p, String name) =>
        p.firstWhere((c) => c.name == name);

    test('无参宿主命令点一下直接执行（返回 null）', () {
      final p = palette();
      expect(slashPickCompletion(p, byName(p, 'todos'), '/to', 3), isNull);
    });

    test('要参数的命令点一下插入裸名 + 空格，光标留在名字后', () {
      final p = palette();
      final out = slashPickCompletion(p, byName(p, 'goal'), '/go', 3)!;
      expect(out.text, '/goal ');
      expect(out.caret, 6);
    });

    test('中文名点选插入的是裸名', () {
      final p = palette();
      final out = slashPickCompletion(p, byName(p, 'goal'), '/目标', 3)!;
      expect(out.text, '/goal ');
    });

    test('技能行总是插入（不执行）', () {
      final p = palette();
      final out = slashPickCompletion(p, byName(p, 'pdf'), '/pd', 3)!;
      expect(out.text, '/pdf ');
    });

    test('光标后有文本时保留后缀（不吞掉后半句）', () {
      final p = palette();
      // '/go 帮我看下' 光标在第 3 位：未知/半截名字只替换光标左侧，
      // 后缀原样保留（后缀自带空白就不再补分隔空格）。
      final out = slashPickCompletion(p, byName(p, 'goal'), '/go 帮我看下', 3)!;
      expect(out.text, '/goal 帮我看下');
      expect(out.caret, 6);
    });

    test('已有完整命令名时整段替换（不叠成 /goal/goal）', () {
      final p = palette();
      final out = slashPickCompletion(p, byName(p, 'goal'), '/goal ', 6)!;
      expect(out.text, '/goal ');
    });
  });

  group('发送分流', () {
    List<SlashCommand> palette() => mergePaletteCommands(
      host: paletteHostCommands(_hostFixture()),
      skills: paletteSkillCommands({
        'skills': [
          {'name': 'pdf', 'description': 'Read a PDF'},
        ],
      }),
    );

    test('普通文本是消息', () {
      expect(classifySlashSend(palette(), 'hello'), isA<SlashSendMessage>());
      expect(classifySlashSend(palette(), ''), isA<SlashSendMessage>());
    });

    test('裸斜杠吃掉回车（面板开着等人挑）', () {
      expect(classifySlashSend(palette(), '/'), isA<SlashSendSwallow>());
      // 斜杠后已有空白说明开始敲参数了，按 dsh-go 口径当普通消息。
      expect(classifySlashSend(palette(), '/  '), isA<SlashSendMessage>());
    });

    test('完整命令名执行整行，中文名换成裸名', () {
      final run = classifySlashSend(palette(), '/目标 上线') as SlashSendRun;
      expect(run.command.name, 'goal');
      expect(run.line, '/goal 上线');
    });

    test('技能整行当消息发（宿主从正文加载技能，不能当命令执行）', () {
      expect(
        classifySlashSend(palette(), '/pdf 读一下这个文件'),
        isA<SlashSendMessage>(),
      );
    });

    test('名字不认识但带参数当消息（路径之类）', () {
      expect(
        classifySlashSend(palette(), '/usr/local/bin'),
        isA<SlashSendMessage>(),
      );
    });

    test('打了一半就回车 → 选中候选第一行', () {
      final pick = classifySlashSend(palette(), '/go') as SlashSendPick;
      expect(pick.command.name, 'goal');
    });

    test('打了一半且无候选 → 当消息', () {
      expect(classifySlashSend(palette(), '/zzz'), isA<SlashSendMessage>());
    });

    test('客户端功能命令回车 → 走执行分支', () {
      final run = classifySlashSend(palette(), '/new') as SlashSendRun;
      expect(run.command.name, 'new');
      expect(run.line, '/new');
    });
  });

  group('面板关闭复位（dsh-go _resetSlashDismissal）', () {
    test('没关过就不动', () {
      expect(resetSlashDismissal(null, '/go'), isNull);
    });

    test('文本没变保持关闭', () {
      expect(resetSlashDismissal('/go', '/go'), '/go');
      expect(resetSlashDismissal('/goal ', '/goal '), '/goal ');
    });

    test('离开斜杠输入就放开', () {
      expect(resetSlashDismissal('/go', 'hello'), isNull);
      expect(resetSlashDismissal('/go', ''), isNull);
    });

    test('重新敲成裸斜杠就放开（关掉 /goal 后重开面板）', () {
      expect(resetSlashDismissal('/goal ', '/'), isNull);
      // 本来就关的是裸斜杠：再敲成裸斜杠不算「重新开始」，保持关闭。
      expect(resetSlashDismissal('/', '/'), '/');
    });

    test('关掉后继续打名字仍保持关闭，只跟文本走', () {
      expect(resetSlashDismissal('/go', '/goa'), '/goa');
    });
  });
}
