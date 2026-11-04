/// 「手机会话」工作区准备（真机反馈 2026-11-04 第 7 项）。
/// 从 chat_state.dart 拆出（宪法 §7 单文件 ≤500 行）。
///
/// message 帧自动建会话不带 workspaceId（ws-basic.ts:39-47，落「未分组」），
/// 所以首条消息前要先有一个手机专属工作区，再走 session-create{workspaceId}。
library;

import '../bridge/dlog.dart';
import '../bridge/gateway.dart';

const mobileWorkspaceDir = '.dsh-mobile';
const mobileWorkspaceTitle = '手机会话';

/// 找到或创建「手机会话」工作区：
/// 1) 已知（本连接内缓存）直接用；2) workspaces 里 title 含「手机」的；
/// 3) 在首个已知工作区的授权根下建 `.dsh-mobile` 目录（幂等）+ REST 登记，
/// 并把名字 PATCH 成「手机会话」。失败返回 null（回落到未分组，不阻断发送）。
Future<String?> ensureMobileWorkspace(
  GatewayClient gateway,
  String? cachedId,
) async {
  if (cachedId != null) return cachedId;
  try {
    final list = await gateway.workspaces();
    for (final w in list) {
      if (w.title.contains('手机')) {
        return w.id;
      }
    }
    // 没有手机工作区：在任一既有工作区的授权根下建目录（拿到 rootId）。
    String? rootId;
    for (final w in list) {
      if (w.rootId.isNotEmpty) {
        rootId = w.rootId;
        break;
      }
    }
    if (rootId == null) return null; // 无授权根可见，放弃（不阻断发送）
    try {
      await gateway.createDirectory(rootId: rootId, path: mobileWorkspaceDir);
    } on RequestException catch (e) {
      // 409 = 目录已存在（幂等），其余错误也继续试登记（登记幂等）。
      DshLog.w('ui mobile-dir create ${e.code}');
    }
    final wsId = await gateway.createWorkspaceRest(
      rootId: rootId,
      path: mobileWorkspaceDir,
    );
    try {
      await gateway.renameWorkspaceRest(wsId, mobileWorkspaceTitle);
    } on RequestException catch (e) {
      DshLog.w('ui mobile-ws rename FAIL ${e.code}'); // 名字不重要，继续
    }
    DshLog.w('ui mobile workspace created id=$wsId');
    return wsId;
  } on RequestException catch (e) {
    DshLog.w('ui mobile workspace FAIL ${e.code} ${e.message}');
    return null;
  }
}
