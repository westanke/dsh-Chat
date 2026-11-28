/// 插件管理桥接层（内核调用 `kernel-call-v1` 的三个插件端点）。
///
/// 端点白名单见 dsh-remote-bridge `src/host/bridge/kernel-allowlist.ts`：
/// `pluginManager/listBundles` / `readBundleDetail` / `setBundleEnabled`。
/// 内核端参数是严格的 wire key（不是 App 内的字段名）：
/// - `readBundleDetail`：`{name, language}`，两个都是必填；
/// - `setBundleEnabled`：`{name, enabled}`；
/// - `listBundles`：无参数。
///
/// 这里只做「调用 + 容错解析 + 中文错误」，不缓存、不持有 UI 状态；
/// 面板每次需要最新数据时重新拉取。
library;

import 'gateway.dart';

/// 面板注入用的最小内核调用签名（生产默认走 [GatewayClient.kernelCall]）。
///
/// 测试可以造一个 [GatewayClient] 子类，自己实现同名 `kernelCall` 并把它
/// 传进来——`kernelCall` 在 SDK 里是 extension，不能被 `@override`。
typedef PluginKernelCall = Future<KernelCallResult> Function(
  String endpoint,
  Map<String, dynamic>? args,
);

/// 一个已安装的插件包（对内核 `BundleInfo` 的 App 侧投影）。
///
/// 内核字段随版本演进，这里全部按可选解析：缺字段只影响展示，不影响列表。
class PluginBundle {
  const PluginBundle({
    required this.id,
    required this.name,
    this.title = '',
    this.version = '',
    this.description = '',
    this.enabled = false,
    this.installed = false,
    this.official = false,
    this.availability = '',
    this.readOnlyReason = '',
    this.errorText = '',
    this.entries = const <PluginEntry>[],
    this.permissions = const <String>[],
  });

  /// 内核里的 `name`（也是 `readBundleDetail` / `setBundleEnabled` 的 `name`）。
  final String id;

  /// 包名（通常与 [id] 相同，保留独立字段以便内核扩展）。
  final String name;

  /// 本地化标题；缺省时为空，展示用 [displayTitle]。
  final String title;
  final String version;
  final String description;
  final bool enabled;
  final bool installed;
  final bool official;

  /// `installation` / `profile` / `missing`，未知时为空。
  final String availability;

  /// `management-required` / `unaddressable`，未知时为空。
  final String readOnlyReason;

  /// 内核返回的管理错误（`ManagementError.diagnostic`），无错误时为空。
  final String errorText;

  /// 插件提供的入口（内核 `rows`）。
  final List<PluginEntry> entries;

  /// 如果插件清单里带权限声明就展示；当前内核不保证提供。
  final List<String> permissions;

  /// 列表/标题里给人看的名字：标题 → 包名 → id。
  String get displayTitle {
    if (title.isNotEmpty) return title;
    if (name.isNotEmpty) return name;
    return id;
  }

  /// 是否有可展示的权限声明。
  bool get hasPermissions => permissions.isNotEmpty;

  /// 是否允许在主机的插件管理里切换（只读插件或管理受限时为 false）。
  bool get manageable =>
      readOnlyReason.isEmpty && errorText.isEmpty && availability != 'missing';

  PluginBundle copyWith({bool? enabled}) => PluginBundle(
        id: id,
        name: name,
        title: title,
        version: version,
        description: description,
        enabled: enabled ?? this.enabled,
        installed: installed,
        official: official,
        availability: availability,
        readOnlyReason: readOnlyReason,
        errorText: errorText,
        entries: entries,
        permissions: permissions,
      );

  /// 容错解析，字段名兼容 `id` / `name` / `bundleName` 与本地化 `meta`。
  factory PluginBundle.fromJson(Map<String, dynamic> json) {
    final meta = _mapValue(json['meta']);
    final rows = json['rows'];
    final entries = <PluginEntry>[];
    if (rows is List) {
      for (final rawRow in rows) {
        final row = _mapValue(rawRow);
        if (row == null) continue;
        final entry = PluginEntry.fromJson(row);
        if (entry.label.isNotEmpty) entries.add(entry);
      }
    }

    final readOnlyReason = _stringValue(json['readOnlyReason']);
    final error = _mapValue(json['error']);
    final permissions = <String>[
      ..._stringList(json['permissions']),
      ..._stringList(json['scopes']),
    ];

    final id = _firstNonEmpty(<Object?>[
      json['id'],
      json['name'],
      json['bundleName'],
      json['package'],
    ]);
    final name = _firstNonEmpty(<Object?>[
      json['name'],
      json['id'],
      json['bundleName'],
    ]);

    return PluginBundle(
      id: id,
      name: name,
      title: _localized(json['title']).isNotEmpty
          ? _localized(json['title'])
          : _localized(meta?['title']),
      version: _stringValue(json['version']),
      description: _localized(meta?['description']).isNotEmpty
          ? _localized(meta?['description'])
          : _stringValue(json['description']),
      enabled: _boolValue(json['enabled']) ?? false,
      installed: _boolValue(json['installed']) ?? false,
      official: _boolValue(json['official']) ?? false,
      availability: _stringValue(json['availability']),
      readOnlyReason: readOnlyReason,
      errorText: error == null
          ? ''
          : (_stringValue(error['diagnostic']).isNotEmpty
              ? _stringValue(error['diagnostic'])
              : _stringValue(error['code'])),
      entries: List<PluginEntry>.unmodifiable(entries),
      permissions: List<String>.unmodifiable(permissions.toSet()),
    );
  }
}

/// 插件入口（内核 `BundleRowInfo` 的 UI 侧投影）。
class PluginEntry {
  const PluginEntry({
    this.rowId = '',
    this.moduleName = '',
    this.entryId = '',
    this.title = '',
  });

  final String rowId;
  final String moduleName;
  final String entryId;
  final String title;

  String get label {
    if (title.isNotEmpty) return title;
    if (moduleName.isNotEmpty) return moduleName;
    if (entryId.isNotEmpty) return entryId;
    return rowId;
  }

  factory PluginEntry.fromJson(Map<String, dynamic> json) {
    final meta = _mapValue(json['meta']);
    return PluginEntry(
      rowId: _stringValue(json['rowId']),
      moduleName: _stringValue(json['moduleName']),
      entryId: _stringValue(json['entryId']),
      title: _localized(meta?['title']),
    );
  }
}

/// 插件说明文档（内核 `BundleDetail`）：找到有 markdown，没找到 `found=false`。
class PluginDetail {
  const PluginDetail({
    required this.found,
    this.origin = '',
    this.path = '',
    this.markdown = '',
  });

  const PluginDetail.none() : this(found: false);

  final bool found;

  /// `locale` / `readme`。
  final String origin;
  final String path;
  final String markdown;

  bool get hasMarkdown => found && markdown.trim().isNotEmpty;

  factory PluginDetail.fromJson(Object? value) {
    final map = _mapValue(value);
    if (map == null) return const PluginDetail.none();
    final status = _stringValue(map['status']);
    final markdown = _stringValue(map['markdown']);
    if (status == 'found' || (status.isEmpty && markdown.isNotEmpty)) {
      return PluginDetail(
        found: true,
        origin: _stringValue(map['origin']),
        path: _stringValue(map['path']),
        markdown: markdown,
      );
    }
    return const PluginDetail.none();
  }
}

/// 插件管理门面：能力探测 + 三个内核端点 + 中文错误。
class PluginCenter {
  PluginCenter(
    GatewayClient gateway, {
    PluginKernelCall? kernelCall,
    this.kernelAvailableOverride,
  })  : _gateway = gateway,
        _kernelCall = kernelCall ??
            ((String endpoint, Map<String, dynamic>? args) =>
                gateway.kernelCall(endpoint, args: args));

  static const listBundlesEndpoint = 'pluginManager/listBundles';
  static const readBundleDetailEndpoint = 'pluginManager/readBundleDetail';
  static const setBundleEnabledEndpoint = 'pluginManager/setBundleEnabled';

  final GatewayClient _gateway;
  final PluginKernelCall _kernelCall;

  /// 测试/上层强制指定能力状态；null 表示按连接能力位与端点目录实时判断。
  final bool? kernelAvailableOverride;

  /// 是否具备插件管理能力：`kernel-call-v1` 能力位 + 端点目录里有 listBundles。
  ///
  /// 面板先用它决定「加载」还是「当前连接不支持插件管理」占位；
  /// 端点目录在连接/重连后才会有值，所以这里每次实时读。
  bool get available {
    final forced = kernelAvailableOverride;
    if (forced != null) return forced;
    return _gateway.kernelCallsEnabled &&
        _gateway.kernelEndpoint(listBundlesEndpoint) != null;
  }

  Future<List<PluginBundle>> listPlugins() async {
    _ensureAvailable();
    final result = await _invoke(listBundlesEndpoint, null);
    if (!result.ok) throw _failure(result, '读取插件列表');
    final raw = _pluginArray(result.value);
    if (raw == null) {
      throw RequestException('BAD_REPLY', '插件列表应答格式不正确：缺少 bundles/items 数组');
    }
    final bundles = <PluginBundle>[];
    for (final item in raw) {
      final map = _mapValue(item);
      if (map == null) continue;
      final bundle = PluginBundle.fromJson(map);
      if (bundle.id.isNotEmpty) bundles.add(bundle);
    }
    if (raw.isNotEmpty && bundles.isEmpty) {
      throw RequestException('BAD_REPLY', '插件列表应答里没有可识别的插件');
    }
    return bundles;
  }

  /// 读取插件说明文档。`language` 是内核必填参数（BCP47），面板固定中文。
  Future<PluginDetail> pluginDetail(
    String id, {
    String language = 'zh-CN',
  }) async {
    _ensureAvailable();
    final name = id.trim();
    if (name.isEmpty) {
      throw RequestException('BAD_REQUEST', '插件标识为空，无法读取详情');
    }
    final result = await _invoke(readBundleDetailEndpoint, <String, dynamic>{
      'name': name,
      'language': language,
    });
    if (!result.ok) throw _failure(result, '读取插件详情');
    if (result.value == null) {
      throw RequestException('BAD_REPLY', '插件详情应答为空');
    }
    return PluginDetail.fromJson(result.value);
  }

  /// 切换插件启用状态，返回操作后应展示的启用状态。
  ///
  /// 返回 `true` 表示插件现在处于启用（或已写入、重启后生效）状态。
  /// 主机明确拒绝、应用失败或取消时抛 [RequestException]（message 为中文）。
  Future<bool> setPluginEnabled(String id, bool enabled) async {
    _ensureAvailable();
    final name = id.trim();
    if (name.isEmpty) {
      throw RequestException('BAD_REQUEST', '插件标识为空，无法切换开关');
    }
    final result = await _invoke(setBundleEnabledEndpoint, <String, dynamic>{
      'name': name,
      'enabled': enabled,
    });
    if (!result.ok) throw _failure(result, enabled ? '启用插件' : '停用插件');

    if (result.value is bool) return result.value! as bool;
    final change = result.object;
    if (change == null) return enabled;

    final application = _stringValue(change['application']);
    final error = _mapValue(change['error']);
    if (application == 'failed' || error != null) {
      final detail = error == null
          ? ''
          : (_stringValue(error['diagnostic']).isNotEmpty
              ? _stringValue(error['diagnostic'])
              : _stringValue(error['code']));
      final reason = detail.isEmpty ? '' : '：$detail';
      throw RequestException('PLUGIN_APPLY_FAILED', '插件「$name」开关未生效$reason');
    }
    if (application == 'cancelled') {
      throw RequestException('PLUGIN_CANCELLED', '插件「$name」的开关操作被取消');
    }
    return _boolValue(change['enabled']) ?? enabled;
  }

  void _ensureAvailable() {
    if (!available) {
      throw RequestException('NOT_SUPPORTED', '当前连接不支持插件管理');
    }
  }

  Future<KernelCallResult> _invoke(
    String endpoint,
    Map<String, dynamic>? args,
  ) async {
    try {
      return await _kernelCall(endpoint, args);
    } on RequestException {
      rethrow;
    } catch (_) {
      throw RequestException('PLUGIN_CALL_FAILED', '插件管理请求失败，请检查连接后重试');
    }
  }

  RequestException _failure(KernelCallResult result, String action) {
    final code = result.code ?? 'KERNEL_FAILED';
    final detail = result.message?.trim() ?? '';
    final reason = switch (code) {
      'gateway/endpoint-unknown' ||
      'kernel/endpoint-unknown' ||
      'ENDPOINT_NOT_FOUND' =>
        '当前主机的内核没有提供「$action」能力',
      'gateway/capability-missing' ||
      'CAPABILITY_MISSING' =>
        '当前连接没有内核调用能力，无法$action',
      'gateway/arguments-invalid' ||
      'ARGS_INVALID' =>
        '插件管理参数与主机版本不匹配，无法$action',
      'gateway/access-denied' ||
      'gateway/scope-denied' ||
      'PERMISSION_DENIED' =>
        '当前主机没有授权$action',
      'gateway/timeout' || 'kernel/timeout' || 'TIMEOUT' => '$action超时，请重试',
      'NOT_CONNECTED' || 'gateway/not-connected' => '连接已断开，无法$action',
      _ => '',
    };
    if (reason.isNotEmpty) {
      return RequestException(
        code,
        detail.isEmpty ? reason : '$reason（$detail）',
      );
    }
    if (detail.isNotEmpty) {
      return RequestException(code, '插件管理失败：$detail');
    }
    return RequestException(code, '插件管理失败（$code）');
  }

  /// 内核列表应答可以是裸数组，也可以是 `{bundles|items|plugins|data: [...]}`。
  List<Object?>? _pluginArray(Object? value, [int depth = 0]) {
    if (value is List) return value;
    if (value is Map && depth < 2) {
      for (final key in const <String>['bundles', 'items', 'plugins', 'data']) {
        final inner = value[key];
        if (inner is List) return inner;
        if (inner is Map) {
          final nested = _pluginArray(inner, depth + 1);
          if (nested != null) return nested;
        }
      }
    }
    return null;
  }
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String _stringValue(Object? value) => value is String ? value.trim() : '';

String _firstNonEmpty(List<Object?> values) {
  for (final value in values) {
    final text = _stringValue(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

bool? _boolValue(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
      case 'on':
        return true;
      case 'false':
      case '0':
      case 'no':
      case 'off':
        return false;
    }
  }
  return null;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  final out = <String>[];
  for (final item in value) {
    final text = _stringValue(item);
    if (text.isNotEmpty) out.add(text);
  }
  return out;
}

/// 本地化文本：字符串原样用；map 先中文，再英文，再任取一个字符串。
String _localized(Object? value) {
  if (value is String) return value.trim();
  if (value is! Map) return '';
  for (final preferred in const <String>['zh-cn', 'zh-hans', 'zh', 'en']) {
    for (final entry in value.entries) {
      if (entry.key.toString().toLowerCase() != preferred) continue;
      final text = _stringValue(entry.value);
      if (text.isNotEmpty) return text;
    }
  }
  for (final entry in value.entries) {
    final text = _stringValue(entry.value);
    if (text.isNotEmpty) return text;
  }
  return '';
}
