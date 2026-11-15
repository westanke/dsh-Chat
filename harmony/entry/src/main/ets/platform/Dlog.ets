/**
 * hilog 封装（宪法 §7：禁 print，鸿蒙日志走 hilog；对应安卓 dlog.dart）。
 * domain 0xD5C0 + 前缀 'Dsh'；debug 级仅在调试构建输出。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xD5C0;
const TAG: string = 'Dsh';

export class Dlog {
  static info(message: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', message);
  }

  static warn(message: string): void {
    hilog.warn(DOMAIN, TAG, '%{public}s', message);
  }

  static error(message: string): void {
    hilog.error(DOMAIN, TAG, '%{public}s', message);
  }
}
