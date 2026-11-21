/**
 * 斜杠面板的取数（宿主命令 + 会话技能 → 合并清单）—— 从 components/Composer.ets
 * 下沉到 core，让输入条只搬状态（对齐安卓 composer.dart 的 _ensureCommands 分层）。
 *
 * 队列里两项互不依赖，并行取：
 * - 宿主：`GatewayApi.listCommands`（桥 `commands` 帧），失败不挡客户端命令；
 * - 技能：内核 `skills/list`，走 `dshrb-v1` 通用调用面；桥没放行 / 没协商 → 空表。
 *
 * 纯逻辑（只依赖 core 内模块），node 直测。
 */

import { JsonMap } from './JsonAccess';
import { SlashCommand, SlashCommandList } from './Content';
import {
  K_SKILLS_LIST,
  SKILLS_LIST_TIMEOUT_MS,
  mergePaletteCommands,
  paletteHostCommands,
  paletteSkillCommands,
  skillsListArgs,
} from './SlashCommands';
import { kernelCallOn, kernelEndpointOf } from './GatewayKernel';
import { KernelCallResult } from './KernelCall';
import { GatewayApi } from './GatewayApi';
import { GatewayClient } from './GatewayClient';

/** 桥 `commands` 帧 → 面板宿主行（已中文化、已去隐藏项）。 */
export function hostPaletteFrom(data: JsonMap): SlashCommand[] {
  return paletteHostCommands(SlashCommandList.fromJson(data).commands);
}

/** 会话技能 → 面板技能行（端点不可用或调用失败都给空表，绝不抛）。 */
export function loadSkillPaletteOn(client: GatewayClient, sessionId: string): Promise<SlashCommand[]> {
  if (kernelEndpointOf(client, K_SKILLS_LIST) === null) {
    return Promise.resolve<SlashCommand[]>([]);
  }
  return kernelCallOn(client, K_SKILLS_LIST, skillsListArgs(sessionId), SKILLS_LIST_TIMEOUT_MS)
    .then((res: KernelCallResult): SlashCommand[] =>
      res.ok ? paletteSkillCommands(res.value) : [])
    .catch((): SlashCommand[] => []);
}

/** 整张面板清单：宿主 + 技能 → 合并（客户端四条功能命令在 merge 里恒在最前）。 */
export function loadPaletteCommands(api: GatewayApi, client: GatewayClient,
                                    sessionId: string): Promise<SlashCommand[]> {
  const host: Promise<SlashCommand[]> = api.listCommands(sessionId)
    .then((data: JsonMap): SlashCommand[] => hostPaletteFrom(data))
    .catch((): SlashCommand[] => []); // 宿主帧失败不挡客户端功能命令（安卓口径）
  return Promise.all([host, loadSkillPaletteOn(client, sessionId)])
    .then((parts: SlashCommand[][]): SlashCommand[] =>
      mergePaletteCommands(parts[0], parts[1]));
}
