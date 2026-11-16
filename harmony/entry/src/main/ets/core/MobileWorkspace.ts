/**
 * 手机工作区保障 —— 从 mobile_workspace.dart + chat_history_actions.dart 拆出
 * （ChatStore 单文件超 500 行违宪，2026-11-16 拆分；core 纯逻辑，node 直测）。
 */

import { ChatMessage } from './HistoryPage';
import { DshWorkspace } from './Models';
import { GatewayApi } from './GatewayApi';
import { SessionLocation } from './SessionLocation';
import { RequestException } from './GatewayEvents';
import type { ChatStore } from './ChatStore';

export const MOBILE_WORKSPACE_DIR: string = '.dsh-mobile';
export const MOBILE_WORKSPACE_TITLE: string = '手机会话';

/** 已加载的最小 seq（下一页 beforeSeq）；null = 没有可翻页的消息。 */
export function oldestSeqOf(messages: ChatMessage[]): number | null {
  for (const m of messages) {
    if (m.seq >= 0) {
      return m.seq;
    }
  }
  return null;
}

/**
 * 找到或创建「手机会话」工作区：已知缓存 → title 含「手机」→ 在首个
 * 授权根下建 `.dsh-mobile`（幂等）+ REST 登记 + PATCH 改名。
 * 失败回 null（回落未分组，不阻断发送）。
 */
export function ensureMobileWorkspace(api: GatewayApi,
  cachedId: string | null): Promise<string | null> {
  if (cachedId !== null) {
    return Promise.resolve(cachedId);
  }
  return api.workspaces().then((workspaces: DshWorkspace[]): Promise<string | null> => {
    for (const w of workspaces) {
      if (w.title.indexOf('手机') >= 0) {
        return Promise.resolve(w.id);
      }
    }
    let rootId: string = '';
    for (const w of workspaces) {
      if (w.rootId !== '') {
        rootId = w.rootId;
        break;
      }
    }
    if (rootId === '') {
      return Promise.resolve(null); // 无授权根可见，放弃（不阻断发送）
    }
    return api.createDirectory(rootId, MOBILE_WORKSPACE_DIR)
      .catch((e: Error): void => {
        // 409 = 目录已存在（幂等），其余错误也继续试登记（登记幂等）。
      })
      .then((): Promise<string> => {
        return api.createWorkspaceRest(rootId, MOBILE_WORKSPACE_DIR);
      })
      .then((wsId: string): Promise<string | null> => {
        return api.renameWorkspaceRest(wsId, MOBILE_WORKSPACE_TITLE)
          .catch((e: Error): void => {
            // 名字不重要，继续。
          })
          .then((): Promise<string | null> => {
            return Promise.resolve(wsId);
          });
      })
      .catch((e: Error): Promise<string | null> => {
        return Promise.resolve(null); // 失败回落未分组，不阻断发送
      });
  }).catch((e: Error): Promise<string | null> => {
    return Promise.resolve(null);
  });
}

/**
 * 首条消息前准备会话通道：ensureMobileWorkspace → session-create{workspaceId}。
 * 失败不阻断发消息（退回 message 帧自动建，落未分组）。
 * ChatStore 循环引用走 import type（仅类型位置）。
 */
export function prepareSessionFor(store: ChatStore): Promise<void> {
  if (store.sessionId !== null) {
    return Promise.resolve();
  }
  const self: ChatStore = store;
  // 选了工作目录 → session-create{rootId,cwd}（会话落「未分组」）；
  // 失败必须显式报错、不静默回退手机会话（等于建到了用户没选的地方）。
  const loc: SessionLocation | null = store.pendingLocation;
  if (loc !== null) {
    store.pendingLocation = null; // 目录已随会话落位，历史会话不受影响
    return store.api.createSessionAt(loc.rootId, loc.cwd).then((sid: string): void => {
      self.sessionId = sid;
      self.pendingSessionId = sid;
    }).catch((e: Error): void => {
      if (e instanceof RequestException) {
        self.lastError = '新建会话失败：' + e.message;
        self.changed();
        return;
      }
      throw e;
    });
  }
  return ensureMobileWorkspace(store.api, store.mobileWorkspaceId)
    .then((wsId: string | null): Promise<void> => {
      if (wsId === null) {
        return Promise.resolve(); // 落 message 帧自动建（未分组）
      }
      return self.api.createSessionInWorkspace(wsId).then((sid: string): void => {
        self.mobileWorkspaceId = wsId;
        self.sessionId = sid;
        self.pendingSessionId = sid;
      }).catch((e: Error): void => {
        // 建会话失败不阻断发消息：退回 message 帧自动建（落未分组）。
      });
    });
}
