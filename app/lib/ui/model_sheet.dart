/// 模型选择面板（真机反馈 2026-11-04 第 3 项）：models 帧拉清单，
/// select-model 帧切换；对照 companion ChatSheets/ModelSheetGroups。
///
/// 两种形态（问题1：新建会话还没有会话号）：
/// - 有 [sessionId]：会话维度清单（current/routable/groups/failures），
///   确认时发 select-model 帧，返回**服务端回传的**选中三元组。
/// - 无 [sessionId]：全局目录（default-model 帧，只有 groups/failures），
///   确认时不发任何帧，直接返回本地选中的三元组（由调用方在建会话后补应用）。
library;

import 'package:material_ui/material_ui.dart';

import '../bridge/gateway.dart';
import '../bridge/models_view.dart';
import '../design/tokens.dart';
import 'window_class.dart';

/// 弹出模型选择面板。返回选中的模型三元组；取消/失败返回 null。
///
/// 有 [sessionId] 时确认会真的切模型（select-model 帧），返回值是服务端
/// 回传的那份（`data.selected`），不是本地猜的 —— 外层拿它刷新 chip，
/// 避免「界面显示的是上一个模型、实际跑的是另一个」。
/// 无 [sessionId] 时只列目录，返回本地选中的三元组，由外层在建会话后补应用。
Future<ModelSelection?> showModelSheet(
  BuildContext context, {
  required DsColors colors,
  required GatewayClient gateway,
  String? sessionId,
}) async {
  final hasSession = sessionId != null && sessionId.isNotEmpty;
  List<ModelProviderGroup> groups;
  List<ModelFailure> failures;
  String? currentProvider = '';
  String? currentModel = '';
  String? currentEffort;
  var routable = true;

  if (hasSession) {
    SessionModels? models;
    String? error;
    try {
      models = SessionModels.parse(await gateway.sessionModels(sessionId));
    } on RequestException catch (e) {
      error = e.message;
    }
    if (!context.mounted) return null;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('模型清单获取失败：$error')),
      );
      return null;
    }
    if (models == null) return null;
    groups = models.groups;
    failures = models.failures;
    routable = models.routable;
    currentProvider = models.current.provider;
    currentModel = models.current.model;
    currentEffort = models.current.reasoningEffort;
  } else {
    ModelCatalog? catalog;
    String? error;
    try {
      catalog = ModelCatalog.parse(await gateway.defaultModelCatalog());
    } on RequestException catch (e) {
      error = e.message;
    }
    if (!context.mounted) return null;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('模型清单获取失败：$error')),
      );
      return null;
    }
    if (catalog == null) return null;
    groups = catalog.groups;
    failures = catalog.failures;
  }

  String? pendingProvider = currentProvider.isEmpty ? null : currentProvider;
  String? pendingModel = currentModel.isEmpty ? null : currentModel;
  String? pendingEffort = currentEffort;
  // 分组收缩状态（真机反馈第 4 项）：默认只展开当前供应商，其余折叠。
  final expanded = <String>{if (currentProvider.isNotEmpty) currentProvider};

  final selection = await showModalBottomSheet<ModelSelection>(
    context: context,
    constraints: modalSheetConstraints(context),
    backgroundColor: colors.bgLayer1,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(DsSpacing.settingsCardRadius),
      ),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(DsSpacing.settingsCardPadH),
                child: Row(
                  children: [
                    Text(
                      hasSession ? '调整模型' : '选择模型',
                      style: DsTypography.baseStrong.copyWith(
                        color: colors.labelPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (!routable || failures.isNotEmpty)
                      Icon(Icons.cloud_off_outlined,
                          size: 18, color: colors.settingsWarnFg),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final g in groups) ...[
                      // 供应商分组头（可点收缩；真机反馈第 4 项）。
                      InkWell(
                        onTap: () => setSheetState(() {
                          if (!expanded.remove(g.id)) expanded.add(g.id);
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DsSpacing.settingsCardPadH,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              Text(
                                g.name,
                                style: DsTypography.smallStrong.copyWith(
                                  color: colors.labelSecondary,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                expanded.contains(g.id)
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 18,
                                color: colors.labelTertiary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 折叠组只留组头；当前选中的模型即使组被折叠也提示一行。
                      if (expanded.contains(g.id))
                        for (final m in g.models)
                          ListTile(
                            dense: true,
                            leading: Icon(
                              pendingProvider == g.id && pendingModel == m.id
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              size: 20,
                              color: pendingProvider == g.id &&
                                      pendingModel == m.id
                                  ? colors.brand
                                  : colors.labelTertiary,
                            ),
                            title: Text(
                              m.name,
                              style: DsTypography.base.copyWith(
                                color: colors.labelPrimary,
                              ),
                            ),
                            subtitle: m.reasoning == null ||
                                    m.reasoning!.efforts.isEmpty
                                ? null
                                : Wrap(
                                    spacing: 6,
                                    children: [
                                      for (final e in m.reasoning!.efforts)
                                        ChoiceChip(
                                          label: Text(
                                            reasoningEffortLabel(e.id),
                                            style: DsTypography.caption,
                                          ),
                                          selected: pendingProvider == g.id &&
                                              pendingModel == m.id &&
                                              pendingEffort == e.id,
                                          onSelected: (_) => setSheetState(() {
                                            pendingProvider = g.id;
                                            pendingModel = m.id;
                                            pendingEffort = e.id;
                                          }),
                                        ),
                                    ],
                                  ),
                            onTap: () => setSheetState(() {
                              pendingProvider = g.id;
                              pendingModel = m.id;
                              pendingEffort = m.reasoning?.defaultEffort;
                            }),
                          ),
                      if (!expanded.contains(g.id) &&
                          pendingProvider == g.id &&
                          pendingModel != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: DsSpacing.settingsCardPadH + 6,
                            bottom: 6,
                          ),
                          child: Text(
                            g.models
                                    .where((m) => m.id == pendingModel)
                                    .firstOrNull
                                    ?.name ??
                                pendingModel!,
                            style: DsTypography.small.copyWith(
                              color: colors.brand,
                            ),
                          ),
                        ),
                    ],
                    if (failures.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(
                          DsSpacing.settingsCardPadH,
                        ),
                        child: Text(
                          '以下服务暂不可用：${failures.map((f) => f.provider).join('、')}',
                          style: DsTypography.small.copyWith(
                            color: colors.settingsWarnFg,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(DsSpacing.settingsCardPadH),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.brand,
                    foregroundColor: colors.onBrand,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: pendingProvider == null || pendingModel == null
                      ? null
                      : () async {
                          final nav = Navigator.of(sheetContext);
                          final messenger = ScaffoldMessenger.of(sheetContext);
                          if (!hasSession) {
                            // 没有会话：只回本地选择，等会话建好再补应用。
                            nav.pop(
                              ModelSelection(
                                provider: pendingProvider!,
                                model: pendingModel!,
                                reasoningEffort: pendingEffort,
                              ),
                            );
                            return;
                          }
                          try {
                            final reply = await gateway.selectModel(
                              sessionId: sessionId,
                              provider: pendingProvider!,
                              model: pendingModel!,
                              reasoningEffort: pendingEffort,
                            );
                            final selected = parseSelectModelReply(reply);
                            if (selected == null) {
                              messenger.showSnackBar(const SnackBar(
                                content: Text('切换失败：服务端应答异常'),
                              ));
                              return;
                            }
                            // 回服务端那份：界面显示与实际运行必须是同一个模型。
                            nav.pop(selected);
                          } on RequestException catch (e) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('切换失败：${e.message}')),
                            );
                          }
                        },
                  child: Text(hasSession ? '确认切换' : '确认选择'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return selection;
}
