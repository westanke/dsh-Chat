import 'package:flutter_test/flutter_test.dart';

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
}
