/// 模型选择面板（真机反馈 2026-11-04 第 3 项）：models 帧拉清单，
/// select-model 帧切换；对照 companion ChatSheets/ModelSheetGroups。
library;

import 'package:flutter/material.dart';

import '../bridge/gateway.dart';
import '../bridge/models_view.dart';
import '../design/tokens.dart';

/// 弹出模型选择面板。返回是否切换成功（用于外层刷新）。
Future<bool> showModelSheet(
  BuildContext context, {
  required DsColors colors,
  required GatewayClient gateway,
  required String sessionId,
}) async {
  SessionModels? models;
  String? error;
  try {
    models = SessionModels.parse(await gateway.sessionModels(sessionId));
  } on RequestException catch (e) {
    error = e.message;
  }
  if (!context.mounted) return false;
  if (error != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('模型清单获取失败：$error')),
    );
    return false;
  }
  if (models == null) return false;

  final current = models.current;
  final groups = models.groups;
  final failures = models.failures;
  final routable = models.routable;
  String? pendingProvider = current.provider;
  String? pendingModel = current.model;
  String? pendingEffort = current.reasoningEffort;
  // 分组收缩状态（真机反馈第 4 项）：默认只展开当前供应商，其余折叠。
  final expanded = <String>{if (current.provider.isNotEmpty) current.provider};

  final changed = await showModalBottomSheet<bool>(
    context: context,
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
                      '调整模型',
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
                            nav.pop(true);
                          } on RequestException catch (e) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('切换失败：${e.message}')),
                            );
                          }
                        },
                  child: const Text('确认切换'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return changed == true;
}
