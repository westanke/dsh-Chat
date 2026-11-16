/**
 * 工作步骤展示状态 —— ProcessGroup 展开状态与自动收起时机的收口（chat-state 层）。
 *
 * 职责（UI 组件层只渲染与转发，状态全在这里，node 直测）：
 * - expandedGroups: Map<string, boolean> —— 过程组展开 key（core/WorkSteps.
 *   processGroupKey：组内首个 callId，无 callId 用 'seq<seq>'）；每条带 version
 *   供 MessageList 的 @Prop version @Watch 链路刷新（坑位：子组件收父 @State
 *   数组一律 @Prop；store 派生值必须在 setNotify 里抄进 @State）。
 * - applyDetail(detail)：切档联动——concise/standard 清空展开；detailed 不动；
 *   verbose 全展开（verbose 档默认展开，收起时机永不自动收）。
 * - collapseTiming='completion'：轮 committed（流式结束）后收起该轮组；
 *   ='next-input'：send() 时收起当前展开组；verbose 永不自动。
 * - selectAgentPreset(sessionId, presetId)：走 REST PUT；409 → RequestException
 *   AGENT_PRESET_LOCKED 原样抛给 UI 行内提示；成功后回填 agentPreset 镜像并
 *   loadSessions()（sessions 列表里的 agentPreset 字段要同步）。
 */

import { ChatMessage } from './HistoryPage';
import { WorkStepsDetail, CollapseTiming, groupKeysOfTurn, lastTurnOf } from './WorkSteps';
import { AgentPreset } from './AgentPresets';
import { RequestException } from './GatewayEvents';
import { ChatStore } from './ChatStore';

export class ExpandedGroupsState {
  keys: string[] = [];
  version: number = 0;
}

export class ChatWorkSteps {
  private detail: WorkStepsDetail = 'detailed';
  private timing: CollapseTiming = 'completion';
  private expanded: Map<string, boolean> = new Map<string, boolean>();
  private versionCounter: number = 0;
  private agentPreset: string | null = null;
  private agentPresets: AgentPreset[] = [];

  /** 当前展示档位。 */
  getDetail(): WorkStepsDetail {
    return this.detail;
  }

  /** 当前收起时机。 */
  getTiming(): CollapseTiming {
    return this.timing;
  }

  /** 切展示档位（设置页生效路径）：concise/standard 收拢全部，verbose 全展开。 */
  applyDetail(detail: WorkStepsDetail): void {
    this.detail = detail;
    if (detail === 'concise' || detail === 'standard') {
      this.expanded.clear();
    } else if (detail === 'verbose') {
      // verbose 档全展开：key 集合由 MessageList 按当前消息渲染时对账
      // （isExpanded 对不在集合里的组回 true），这里只清掉手工收起的痕迹。
      this.expanded.clear();
    }
    this.bump();
  }

  /** 切收起时机（不即时动展开集合；只影响后续自动收起点）。 */
  applyTiming(timing: CollapseTiming): void {
    this.timing = timing;
  }

  /** 过程组展开 key 快照（MessageList 渲染用；每次 changed 抄进 @State）。 */
  snapshotExpanded(): ExpandedGroupsState {
    const keys: string[] = [];
    this.expanded.forEach((v: boolean, k: string) => {
      if (v) {
        keys.push(k);
      }
    });
    const st: ExpandedGroupsState = new ExpandedGroupsState();
    st.keys = keys;
    st.version = this.versionCounter;
    return st;
  }

  /** verbose 档：默认展开——未在集合里的组视为展开；其余档未记 = 收起。 */
  isExpanded(key: string): boolean {
    if (this.detail === 'verbose') {
      const off: boolean | undefined = this.expanded.get(key);
      return off === undefined ? true : off;
    }
    const on: boolean | undefined = this.expanded.get(key);
    return on === undefined ? false : on;
  }

  toggle(key: string): void {
    if (this.detail === 'concise') {
      return; // 只渲染折叠行且不可展开。
    }
    const next: boolean = !this.isExpanded(key);
    this.expanded.set(key, next);
    this.bump();
  }

  /** 收起一批组（自动收起与 verbose 手工收起共用；只记收起项）。 */
  collapseKeys(keys: string[]): void {
    for (let i = 0; i < keys.length; i++) {
      this.expanded.set(keys[i], false);
    }
    this.bump();
  }

  /** completion 时机：轮 committed（流式结束分支）后收起该轮全部组。 */
  collapseTurnOnCompletion(messages: ChatMessage[]): void {
    if (this.detail === 'verbose') {
      return;
    }
    this.collapseKeys(groupKeysOfTurn(lastTurnOf(messages)));
  }

  /** next-input 时机：send() 时收起当前展开的全部组。 */
  collapseOnSend(): void {
    if (this.detail === 'verbose') {
      return;
    }
    const keys: string[] = [];
    this.expanded.forEach((v: boolean, k: string) => {
      if (v) {
        keys.push(k);
      }
    });
    this.collapseKeys(keys);
  }

  /** 会话切换/历史重载：展开状态清零（新会话新账）。 */
  resetSessionView(): void {
    this.expanded.clear();
    this.agentPreset = null;
    this.agentPresets = [];
    this.bump();
  }

  // ---- Agent 预设镜像（CodeWorkSheet 第三段渲染） ------------------

  currentAgentPreset(): string | null {
    return this.agentPreset;
  }

  setAgentPreset(preset: string | null): void {
    if (this.agentPreset !== preset) {
      this.agentPreset = preset;
      this.bump();
    }
  }

  cachedAgentPresets(): AgentPreset[] {
    return this.agentPresets;
  }

  setAgentPresets(list: AgentPreset[]): void {
    this.agentPresets = list;
    this.bump();
  }

  private bump(): void {
    this.versionCounter += 1;
  }
}

/**
 * 选 Agent 预设（ChatStore.selectAgentPreset 实现；与 ChatHistory/ChatActions
 * 同款 In-函数挂接模式）。成功后：镜像回填（UI 打勾即时生效）+ 重拉 sessions
 * （sessions 列表里的 agentPreset 字段同步）。
 */
export function selectAgentPresetIn(store: ChatStore, presetId: string): Promise<string> {
  const sid: string = store.sessionId ?? '';
  if (sid === '') {
    return Promise.reject(new RequestException('NO_SESSION', '当前无会话'));
  }
  return store.api.selectAgentPreset(sid, presetId).then((preset: string): string => {
    store.workSteps.setAgentPreset(preset);
    store.loadSessions();
    store.changed();
    return preset;
  });
}
