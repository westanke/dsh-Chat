/**
 * 窗口宽度断点（官方「布局基础」R007）：<600vp 紧凑 / 600–840vp 中等 / ≥840vp 大。
 * 口径与官方 BreakPoints 一致，只是不引 GridRow —— 鸿蒙版的容器是手写 Row/Column，
 * 所以把档位集中成常量 + 纯函数，`pages/Index.ets` 用 mediaquery 监听窗口宽度写进
 * `AppStorage('dshBreakpoint')`，各页面/组件用 `@StorageProp('dshBreakpoint')` 读档位
 * 做最大宽与栅格调整（大屏居中、抽屉加宽）。
 *
 * 纯常量 + 纯函数（不 import 任何 @kit），平台相关的 mediaquery 留在 Index；
 * 放 core 是为了能 node 直测。
 */

/** 紧凑档：手机竖屏（<600vp）。 */
export const BP_SM: string = 'sm';
/** 中等档：折叠屏展开 / 小平板（600–840vp）。 */
export const BP_MD: string = 'md';
/** 大档：平板横屏 / 2in1（≥840vp）。 */
export const BP_LG: string = 'lg';

/** mediaquery 查询串（在 Index 里 matchMediaSync，避免自己算 px→vp）。 */
export const BP_QUERY_MD: string = '(width>=600vp)';
export const BP_QUERY_LG: string = '(width>=840vp)';
/** 两个查询都命中才算大档，否则退到中等/紧凑。 */
export const BP_QUERY_MD_ONLY: string = '(width>=600vp) and (width<840vp)';
export const BP_QUERY_SM: string = '(width<600vp)';

/** 由两个 mediaquery 命中结果推出档位（Index 的 on('change') 回调即用它）。 */
export function breakpointOf(mdMatches: boolean, lgMatches: boolean): string {
  if (lgMatches) {
    return BP_LG;
  }
  if (mdMatches) {
    return BP_MD;
  }
  return BP_SM;
}

/** 是否中等及以上档（≥600vp）。 */
export function atLeastMd(bp: string): boolean {
  return bp === BP_MD || bp === BP_LG;
}

/** 是否大档（≥840vp）。 */
export function isLarge(bp: string): boolean {
  return bp === BP_LG;
}

/**
 * 内容区最大宽（vp）：紧凑档 0（不约束，交给 layoutWeight/百分比），
 * 中等档 720、大档 840，超过就居中留白 —— 官方「大屏不要拉满」口径。
 */
export function contentMaxWidth(bp: string): number {
  if (bp === BP_MD) {
    return 720;
  }
  if (bp === BP_LG) {
    return 840;
  }
  return 0;
}

/** 会话抽屉宽度（vp）：手机上 320 已够，大屏按档加宽避免右侧留白突兀。 */
export function drawerWidth(bp: string): number {
  if (bp === BP_MD) {
    return 352;
  }
  if (bp === BP_LG) {
    return 400;
  }
  // 手机 360vp 屏的 80%（与安卓 sessions_drawer 同口径），大屏才按档加宽。
  return 288;
}

/** 面板（bindSheet）内容最大宽：大屏限 720，避免整屏文字行长过大。 */
export function sheetMaxWidth(bp: string): number {
  if (bp === BP_MD) {
    return 640;
  }
  if (bp === BP_LG) {
    return 720;
  }
  return 0;
}

/** 抽屉推挤比例：大屏推挤更多（内容区留得住），手机 0.8 与安卓同口径。 */
export function drawerFraction(bp: string): number {
  if (bp === BP_LG) {
    return 0.32;
  }
  if (bp === BP_MD) {
    return 0.4;
  }
  return 0.8;
}
