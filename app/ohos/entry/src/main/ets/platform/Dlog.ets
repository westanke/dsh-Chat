/**
 * hilog 封装（宪法 §7：禁 print，鸿蒙日志走 hilog；对应安卓 dlog.dart）。
 * domain 0xD5C0 + TAG 'Dsh'，真机用
 * `hdc shell "hilog -x | grep 'A0D5C0'"` 取。
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
