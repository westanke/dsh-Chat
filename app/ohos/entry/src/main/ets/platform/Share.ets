/**
 * 系统分享（纯文本）—— 安卓 DshPlatform.share 的鸿蒙对应物。
 *
 * 首选 ShareKit（@kit.ShareKit 的 systemShare）：官方系统分享面板，
 * 支持预览与选应用；拿不到再退 Want（action:ohos.want.action.sendData）。
 *
 * 注意：鸿蒙的 Want 分享**不保证**弹出系统面板（安卓 ACTION_SEND
 * createChooser 才是强对应），所以这里以 ShareKit 为主路径。
 *
 * 失败一律回 false（Dart 侧据此提示「暂不可用」，与安卓口径一致）。
 */
import { common, Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { Dlog } from './Dlog';

/** 走 ShareKit 系统分享面板。 */
async function shareViaShareKit(context: common.UIAbilityContext, text: string): Promise<boolean> {
  try {
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
    await controller.show(context, options);
    return true;
  } catch (e) {
    Dlog.warn('shareViaShareKit failed: ' + JSON.stringify(e));
    return false;
  }
}

/** 退路：Want 文本分享。 */
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
  } catch (e) {
    Dlog.warn('shareViaWant failed: ' + JSON.stringify(e));
    return false;
  }
}

/**
 * 分享一段纯文本。true=已调起分享面板；false=空文本或调起失败。
 *
 * 安卓口径：空串直接 false，不拉面板。
 */
export async function shareText(context: common.UIAbilityContext, text: string): Promise<boolean> {
  const trimmed: string = text.trim();
  if (trimmed.length === 0) {
    return false;
  }
  if (await shareViaShareKit(context, trimmed)) {
    return true;
  }
  return await shareViaWant(context, trimmed);
}
