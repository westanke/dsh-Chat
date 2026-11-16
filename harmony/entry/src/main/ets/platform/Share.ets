/**
 * 系统分享（纯文本）—— 安卓 DshPlatform.share 的鸿蒙对应物。
 *
 * 首选 ShareKit 的 systemShare（`@kit.ShareKit`）：SharedData/SharedRecord 用
 * UTD `general.plain-text` + content 装载文本，ShareController.show 拉起系统分享面板。
 * 拿不到 ShareKit（部分设备/版本无该系统能力）时退回 Want `ohos.want.action.sendData`
 * + text/plain 的隐式拉起。两条都失败才回 false（调用方提示「分享暂不可用」，安卓口径）。
 */

import { common, Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';

/** 调用方写入的最近一次分享控制器（面板 dismiss 后可复用，避免重复建）。 */
let lastController: systemShare.ShareController | null = null;

/** ShareKit 路径：拉起系统分享面板。 */
async function shareViaShareKit(context: common.UIAbilityContext, text: string): Promise<boolean> {
  const record: systemShare.SharedRecord = {
    utd: utd.UniformDataType.PLAIN_TEXT,
    content: text
  };
  const data: systemShare.SharedData = new systemShare.SharedData(record);
  const controller: systemShare.ShareController = new systemShare.ShareController(data);
  const options: systemShare.ShareControllerOptions = {
    selectionMode: systemShare.SelectionMode.SINGLE,
    previewMode: systemShare.SharePreviewMode.DEFAULT
  };
  try {
    await controller.show(context, options);
    lastController = controller;
  } catch (err) {
    return false;
  }
  return true;
}

/** Want 兜底路径：隐式 action 唤起能处理 text/plain 的应用。 */
async function shareViaWant(context: common.UIAbilityContext, text: string): Promise<boolean> {
  try {
    const want: Want = {
      action: 'ohos.want.action.sendData',
      type: 'text/plain',
      entities: ['ohos.want.action.entity.share'],
      parameters: {
        text: text
      }
    };
    await context.startAbility(want);
    return true;
  } catch (err) {
    return false;
  }
}

/** 分享一段文本；true=面板已拉起，false=两条路径都不可用。 */
export async function shareText(context: common.UIAbilityContext, text: string): Promise<boolean> {
  const body: string = text.trim();
  if (body.length === 0) {
    return false;
  }
  if (await shareViaShareKit(context, body)) {
    return true;
  }
  return await shareViaWant(context, body);
}

/** 收起分享面板（如果还开着）；忽略失败。 */
export function dismissShare(): void {
  lastController = null;
}
