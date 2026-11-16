/**
 * 应用新版本检测（鸿蒙版）—— 改走华为应用市场。
 *
 * 历史口径（2026-11-16 用户要求改）：鸿蒙版最初照搬安卓的 Gitee/GitHub
 * Release 检查（`core/ReleaseCheck.ts`），但鸿蒙应用只能由 AppGallery 分发，
 * 自更新既不允许也不合规。改为调 AppGallery Kit 的 `updateManager`：
 * - `checkAppUpdate(ctx)` → `updateAvailable`（1=有新版 / 0=最新）
 * - `showUpdateDialog(ctx)` → 由系统弹官方更新对话框（用户在应用市场完成升级）
 *
 * 纯逻辑部分（版本比较、状态文案）留在这里，node 直测；平台调用在入口层
 * （`pages/SettingsView.ets`），因为 `updateManager` 需要 UIAbilityContext。
 */

/** 检查结果（UI 直接照着渲染）。 */
export class UpdateCheckResult {
  /** 是否有新版本。 */
  readonly hasNew: boolean;

  /** 面向用户的说明文案（已本地化，直接上屏）。 */
  readonly message: string;

  /** 平台错误码（'' = 无错误；有错误时 message 里也带）。 */
  readonly errorCode: string;

  constructor(hasNew: boolean, message: string, errorCode: string) {
    this.hasNew = hasNew;
    this.message = message;
    this.errorCode = errorCode;
  }

  static ofNew(): UpdateCheckResult {
    return new UpdateCheckResult(true, '发现新版本，点此前往华为应用市场更新', '');
  }

  static ofLatest(): UpdateCheckResult {
    return new UpdateCheckResult(false, '已是最新版本', '');
  }

  /**
   * 失败降级：errorCode 是 BusinessError.code 的字符串形式。
   * 按 SDK 文档的错误码给出可操作提示（`@hms.core.appgalleryservice.updateManager.d.ts`）。
   */
  static ofError(errorCode: string, detail: string): UpdateCheckResult {
    const msg: string = updateErrorMessage(errorCode, detail);
    return new UpdateCheckResult(false, msg, errorCode);
  }
}

/** 错误码 → 中文提示（SDK：1009400001~1009400007、401）。 */
export function updateErrorMessage(errorCode: string, detail: string): string {
  switch (errorCode) {
    case '1009400001':
      return '检查更新失败：应用市场服务连接失败（SA connect error）';
    case '1009400002':
      return '检查更新失败：应用市场服务请求异常';
    case '1009400003':
      return '检查更新失败：网络不可用';
    case '1009400004':
      return '检查更新失败：应用不在前台';
    case '1009400005':
      return '检查更新失败：未同意隐私协议，请先在系统里同意';
    case '1009400006':
      return '检查更新失败：操作过于频繁，稍后再试';
    case '1009400007':
      return '检查更新失败：其它错误';
    case '401':
      return '检查更新失败：参数错误';
    case 'NOT_IN_MARKET':
      return '当前版本不是从华为应用市场安装的，无法检查更新';
    default: {
      const extra: string = detail.length > 0 ? ('：' + detail) : '';
      return '检查更新失败' + extra;
    }
  }
}

/** 平台未安装/能力不可用时的统一文案（开发者预览版系统常见）。 */
export const NOT_SUPPORTED_MESSAGE: string = '当前系统不支持应用市场更新检查';

/** `checkAppUpdate` 返回值：1=有新版（UpdateAvailableCode.LATER_VERSION_EXIST）。 */
export const UPDATE_AVAILABLE_YES: number = 1;
