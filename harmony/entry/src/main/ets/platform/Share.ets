/**
 * 系统分享（纯文本）—— 安卓 DshPlatform.share 的鸿蒙对应物。
 * Want action 'ohos.want.action.sendData' + text/plain；调用方提示
 * 「分享暂不可用」（安卓 SnackBar 口径）。真机验证阶段确认各厂商
 * 分享面板兼容性（PORT-MAP 待记坑）。
 */

import { common, Want } from '@kit.AbilityKit';

export async function shareText(context: common.UIAbilityContext, text: string): Promise<boolean> {
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
