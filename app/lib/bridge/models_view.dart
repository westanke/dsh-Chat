/// 会话模型视图（models 应答收敛；真机反馈 2026-11-04 第 3 项）。
///
/// 应答形状（ws-models.ts:58，chat-adapter.ts:160-184）：
/// `{sessionId, current:{provider,model,reasoningEffort?}, routable,
///   groups:[{id,name,models:[{id,name,description?,contextWindow?,maxTokens?,
///   reasoning?:{efforts:[{id,name,description?}], defaultEffort?}}]}],
///   failures:[{provider,message}]}`
/// **没有 providers/modelCatalog 字段——groups 就是按 provider 分的组**。
class ModelReasoningEffort {
  const ModelReasoningEffort({required this.id, required this.name});

  factory ModelReasoningEffort.fromJson(Map<String, dynamic> j) =>
      ModelReasoningEffort(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? j['id'] ?? '') as String,
      );

  final String id;
  final String name;
}

class ModelReasoning {
  const ModelReasoning({required this.efforts, this.defaultEffort});

  factory ModelReasoning.fromJson(Map<String, dynamic> j) => ModelReasoning(
    efforts: (j['efforts'] as List? ?? const [])
        .map(
          (e) => ModelReasoningEffort.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
    defaultEffort: j['defaultEffort'] as String?,
  );

  /// 权威 effort 枚举（内核 DeepSeek 全集 off/low/high/max，勿硬编码）。
  final List<ModelReasoningEffort> efforts;
  final String? defaultEffort;
}

class ModelView {
  const ModelView({
    required this.id,
    required this.name,
    this.description,
    this.reasoning,
  });

  factory ModelView.fromJson(Map<String, dynamic> j) => ModelView(
    id: (j['id'] ?? '') as String,
    name: (j['name'] ?? j['id'] ?? '') as String,
    description: j['description'] as String?,
    reasoning: j['reasoning'] is Map
        ? ModelReasoning.fromJson(Map<String, dynamic>.from(j['reasoning'] as Map))
        : null,
  );

  final String id;
  final String name;
  final String? description;
  final ModelReasoning? reasoning;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': ?description,
    'reasoning': ?reasoning == null
        ? null
        : {
            'efforts': reasoning!.efforts
                .map((e) => {'id': e.id, 'name': e.name})
                .toList(),
            'defaultEffort': ?reasoning!.defaultEffort,
          },
  };
}

class ModelProviderGroup {
  const ModelProviderGroup({
    required this.id,
    required this.name,
    required this.models,
  });

  factory ModelProviderGroup.fromJson(Map<String, dynamic> j) =>
      ModelProviderGroup(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? j['id'] ?? '') as String,
        models: (j['models'] as List? ?? const [])
            .map((e) => ModelView.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  final String id;
  final String name;
  final List<ModelView> models;
}

class ModelFailure {
  const ModelFailure({required this.provider, required this.message});

  factory ModelFailure.fromJson(Map<String, dynamic> j) => ModelFailure(
    provider: (j['provider'] ?? '') as String,
    message: (j['message'] ?? '') as String,
  );

  final String provider;
  final String message;
}

/// models 应答整体。
class SessionModels {
  const SessionModels({
    required this.current,
    required this.routable,
    required this.groups,
    required this.failures,
  });

  factory SessionModels.fromJson(Map<String, dynamic> j) => SessionModels(
    current: ModelSelection.fromJson(
      Map<String, dynamic>.from((j['current'] ?? const {}) as Map),
    ),
    routable: j['routable'] == true,
    groups: (j['groups'] as List? ?? const [])
        .map(
          (e) => ModelProviderGroup.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
    failures: (j['failures'] as List? ?? const [])
        .map((e) => ModelFailure.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );

  /// 从 gateway.sessionModels() 的原始 data 收敛。
  static SessionModels parse(Map<String, dynamic> data) =>
      SessionModels.fromJson(data);

  final ModelSelection current;
  final bool routable;
  final List<ModelProviderGroup> groups;
  final List<ModelFailure> failures;
}

/// 当前选中模型三元组（也用于 select-model 应答的 data.selected）。
class ModelSelection {
  const ModelSelection({
    this.provider = '',
    this.model = '',
    this.reasoningEffort,
  });

  factory ModelSelection.fromJson(Map<String, dynamic> j) => ModelSelection(
    provider: (j['provider'] ?? '') as String,
    model: (j['model'] ?? '') as String,
    reasoningEffort: j['reasoningEffort'] as String?,
  );

  final String provider;
  final String model;
  final String? reasoningEffort;

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'model': model,
    'reasoningEffort': ?reasoningEffort,
  };
}

/// 从 select-model 应答（kind=sent）提取 selected 三元组；
/// data.type != 'select-model' 或缺 selected 时返回 null（协议错误，
/// companion WsDomainPorts.kt:216-221 抛 WS_BAD_FRAME，这里交给 UI 提示）。
ModelSelection? parseSelectModelReply(Map<String, dynamic> data) {
  if (data['type'] != 'select-model') return null;
  final selected = data['selected'];
  if (selected is! Map) return null;
  return ModelSelection.fromJson(Map<String, dynamic>.from(selected));
}

/// reasoningEffort 的本地中文标签（off/low/high/max；未知回退原值）。
String reasoningEffortLabel(String id) => switch (id) {
  'off' => '关闭',
  'low' => '低',
  'high' => '高',
  'max' => '最高',
  _ => id,
};
