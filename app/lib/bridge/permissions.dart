import 'gateway.dart';

/// permission-options 应答 → PermissionCatalog（gateway 返回原始 data，
/// 在这层收敛形状，避免 models 层与 UI 层互相 import）。
PermissionCatalog parsePermissionCatalog(Map<String, dynamic> j) =>
    PermissionCatalog.fromJson(j);

/// 权限档位目录与本地化标签（真机反馈 2026-11-04 第 4 项）。
///
/// 权威清单来自服务端 `permission-options` 应答（内核 permissionPresets.catalog()
/// 的透传），**不硬编码四档**：默认部署只有 workspace-write / danger-full-access
/// 两个 preset（read-only 是合法 sandbox 模式但没有默认 preset，切换会失败；
/// auto 只在 live Auto 集成注册时出现；custom 是派生态、永不可切）。
/// UI 上 options 里没有的档位一律不显示。
class PermissionOption {
  const PermissionOption({
    required this.value,
    required this.name,
    this.description,
  });

  factory PermissionOption.fromJson(Map<String, dynamic> j) =>
      PermissionOption(
        value: (j['value'] ?? '') as String,
        name: (j['name'] ?? j['value'] ?? '') as String,
        description: j['description'] as String?,
      );

  /// 切换用档位 id（permission 帧的 name 参数）。
  final String value;

  /// 服务端名称（未知档位的回退显示）。
  final String name;

  /// 服务端描述（可缺省）。
  final String? description;

  Map<String, dynamic> toJson() => {
    'value': value,
    'name': name,
    'description': ?description,
  };

  /// 本地中文标签（对照 companion ChatPermissionMenu.permissionLabel；
  /// 用户口径：仅可查看/工作区读写/完全权限/自动审查）。未识别回退服务端 name。
  String get label => switch (value) {
    'read-only' => '仅可查看',
    'workspace-write' => '工作区读写',
    'danger-full-access' => '完全权限',
    'auto' => '自动审查',
    'custom' => '自定义',
    _ => name,
  };

  /// 本地中文说明；未识别回退服务端 description。
  String? get descriptionLabel => switch (value) {
    'read-only' => '只能查看会话内容，不能写入',
    'workspace-write' => '可以在工作区内读写文件',
    'danger-full-access' => '不受沙箱限制，操作前请确认',
    'auto' => '按风险自动决定是否需要确认',
    _ => (description == null || description!.isEmpty) ? null : description,
  };

  /// 是否需要二次确认（对照 companion：danger-full-access 必须确认）。
  bool get needsConfirm => value == 'danger-full-access';

  /// 派生态，不能作为切换目标（内核保留值）。
  bool get isDerived => value == 'custom';
}

/// permission-options 应答整体（{options, defaultPreset}）。
class PermissionCatalog {
  const PermissionCatalog({required this.options, this.defaultPreset});

  factory PermissionCatalog.fromJson(Map<String, dynamic> j) =>
      PermissionCatalog(
        options: (j['options'] as List? ?? const [])
            .map(
              (e) => PermissionOption.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(),
        defaultPreset: j['defaultPreset'] as String?,
      );

  final List<PermissionOption> options;

  /// 服务端默认档位（只用于「未设置过」时的初始显示，**不当当前值**——
  /// companion Models.kt:230-236 的刻意取舍）。
  final String? defaultPreset;

  /// 可切换的档位（过滤 custom）。
  List<PermissionOption> get switchable =>
      options.where((o) => !o.isDerived).toList();

  Map<String, dynamic> toJson() => {
    'options': options.map((o) => o.toJson()).toList(),
    'defaultPreset': ?defaultPreset,
  };
}

/// 当前会话权限档位的本地中文标签（投影 values.permissions 的 currentValue）。
/// 未知值原样返回，绝不绝不杜撰档位。
String permissionLabelOf(String? value) {
  if (value == null || value.isEmpty) return '权限未设置';
  // 复用 PermissionOption 的映射表（构造一个轻量对象查询）。
  return PermissionOption(value: value, name: value).label;
}

/// 抛错统一走 RequestException（gateway.dart），UI 按 message 展示。
typedef PermissionException = RequestException;
