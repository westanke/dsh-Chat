import 'package:flutter_test/flutter_test.dart';

import 'package:dshchat/bridge/models_view.dart';
import 'package:dshchat/bridge/permissions.dart';

void main() {
  group('PermissionOption', () {
    test('fromJson：value/name/description，缺 name 回退 value', () {
      final o = PermissionOption.fromJson({
        'value': 'workspace-write',
        'name': 'workspace-write',
        'description': 'Write inside workspace',
      });
      expect(o.value, 'workspace-write');
      expect(o.label, '工作区读写');
      expect(o.descriptionLabel, '可以在工作区内读写文件');
      expect(o.needsConfirm, isFalse);
      expect(o.isDerived, isFalse);
    });

    test('四档 + custom 的本地化标签（真机反馈口径）', () {
      const values = {
        'read-only': '仅可查看',
        'workspace-write': '工作区读写',
        'danger-full-access': '完全权限',
        'auto': '自动审查',
        'custom': '自定义',
      };
      for (final entry in values.entries) {
        final o = PermissionOption(value: entry.key, name: entry.key);
        expect(o.label, entry.value, reason: entry.key);
      }
    });

    test('未知档位回退服务端 name，不杜撰', () {
      final o = PermissionOption(value: 'org-x', name: 'Org X');
      expect(o.label, 'Org X');
      expect(o.descriptionLabel, isNull);
    });

    test('danger-full-access 需要二次确认；custom 是派生态不可切', () {
      expect(
        PermissionOption(value: 'danger-full-access', name: '').needsConfirm,
        isTrue,
      );
      expect(
        PermissionOption(value: 'custom', name: '').isDerived,
        isTrue,
      );
    });

    test('toJson round-trip', () {
      final o = PermissionOption(
        value: 'read-only',
        name: 'read-only',
        description: 'd',
      );
      final back = PermissionOption.fromJson(o.toJson());
      expect(back.value, o.value);
      expect(back.name, o.name);
      expect(back.description, 'd');
    });
  });

  group('PermissionCatalog', () {
    test('fromJson 解析 permission-options 应答', () {
      final c = PermissionCatalog.fromJson({
        'options': [
          {'value': 'workspace-write', 'name': 'workspace-write'},
          {'value': 'danger-full-access', 'name': 'danger-full-access'},
          {'value': 'custom', 'name': 'custom'},
        ],
        'defaultPreset': 'workspace-write',
      });
      expect(c.options, hasLength(3));
      expect(c.defaultPreset, 'workspace-write');
      // custom 被过滤（派生态不可切）。
      expect(c.switchable.map((o) => o.value).toList(), [
        'workspace-write',
        'danger-full-access',
      ]);
    });

    test('空 options 与缺席字段容忍（无 scope 时上游可能给空壳）', () {
      final c = PermissionCatalog.fromJson(const {});
      expect(c.options, isEmpty);
      expect(c.defaultPreset, isNull);
      expect(c.switchable, isEmpty);
    });
  });

  test('permissionLabelOf：空值显示「权限未设置」，未知原样', () {
    expect(permissionLabelOf(null), '权限未设置');
    expect(permissionLabelOf(''), '权限未设置');
    expect(permissionLabelOf('workspace-write'), '工作区读写');
    expect(permissionLabelOf('weird-value'), 'weird-value');
  });

group('SessionModels select-model 应答收敛（models 帧）', () {
  test('fromJson：current/routable/groups/failures 全解析', () {
    final m = SessionModels.fromJson({
      'sessionId': 's1',
      'current': {
        'provider': 'deepseek',
        'model': 'deepseek-chat',
        'reasoningEffort': 'high',
      },
      'routable': true,
      'groups': [
        {
          'id': 'deepseek',
          'name': 'DeepSeek',
          'models': [
            {
              'id': 'deepseek-chat',
              'name': 'DeepSeek Chat',
              'reasoning': {
                'efforts': [
                  {'id': 'off', 'name': 'off'},
                  {'id': 'high', 'name': 'high'},
                ],
                'defaultEffort': 'off',
              },
            },
            {'id': 'deepseek-reasoner', 'name': 'DeepSeek Reasoner'},
          ],
        },
      ],
      'failures': [
        {'provider': 'openai', 'message': 'unavailable'},
      ],
    });
    expect(m.routable, isTrue);
    expect(m.current.provider, 'deepseek');
    expect(m.current.model, 'deepseek-chat');
    expect(m.current.reasoningEffort, 'high');
    expect(m.groups, hasLength(1));
    expect(m.groups.single.models, hasLength(2));
    expect(m.groups.single.models.first.reasoning!.efforts.map((e) => e.id),
        ['off', 'high']);
    expect(m.groups.single.models.first.reasoning!.defaultEffort, 'off');
    expect(m.failures.single.provider, 'openai');
  });

  test('parseSelectModelReply：data.type=select-model 才有效', () {
    final ok = parseSelectModelReply({
      'type': 'select-model',
      'sessionId': 's1',
      'accepted': true,
      'selected': {
        'provider': 'deepseek',
        'model': 'deepseek-reasoner',
        'reasoningEffort': 'max',
      },
    });
    expect(ok!.provider, 'deepseek');
    expect(ok.model, 'deepseek-reasoner');
    expect(ok.reasoningEffort, 'max');

    // sent 共享 kind：message 应答 data.type != select-model 必须拒绝。
    expect(parseSelectModelReply({'type': 'message'}), isNull);
    expect(parseSelectModelReply({'type': 'select-model'}), isNull);
  });

  test('ModelSelection toJson round-trip + reasoningEffortLabel', () {
    final s = ModelSelection(
      provider: 'p',
      model: 'm',
      reasoningEffort: 'high',
    );
    final back = ModelSelection.fromJson(s.toJson());
    expect(back.provider, 'p');
    expect(back.reasoningEffort, 'high');
    expect(reasoningEffortLabel('off'), '关闭');
    expect(reasoningEffortLabel('max'), '最高');
    expect(reasoningEffortLabel('weird'), 'weird');
  });
});
}
