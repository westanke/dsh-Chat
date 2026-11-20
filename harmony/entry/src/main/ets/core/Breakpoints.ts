/**
 * 窗口宽度断点（官方「布局基础」R007）：<600vp 紧凑 / 600–840vp 中等 / ≥840vp 大。
 * 口径与官方 BreakPoints 一致，只是不引 GridRow —— 鸿蒙版的容器是手写 Row/Column，
 * 所以把档位集中成常量 + 纯函数，`pages/Index.ets` 用 mediaquery 监听窗口宽度写进
 * `AppStorage('dshBreakpoint')`，各页面/组件用 `@StorageProp('dshBreakpoint')` 读档位
 * 做抽屉加宽等调整；正文列宽另由 `readableColumnWidth(实测宽)` 算（不再按档取固定上限）。
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
 * 正文列基准宽（vp）：**不是上限**，只是「从这往上才开始缓增」的起点。
 * 与安卓 `DsSpacing.readableBaseWidth = 720` 同值同口径。
 */
export const READABLE_BASE_WIDTH: number = 720;

/** 超过基准宽后的缩放比例：列宽 = 可用宽 × 0.9（与安卓 `readableScale` 同值）。 */
export const READABLE_SCALE: number = 0.9;

/** 浮层控件（顶栏 / 输入条）比正文列两侧各收的余量（与安卓 `chatFloatInset` 同值）。 */
export const FLOAT_INSET: number = 14;

/**
 * 正文列宽（vp）：窗口不宽就用满，宽了按 0.9 跟着长，**没有第二道上限**。
 *
 * 用户口径（2026-11-21）：「整个 app 所有都不应该限制 720 宽，应该按照可读屏幕
 * 视图缩放少量」——安卓同轮改成同一条尺（`readableColumnWidth`），鸿蒙这边原先
 * 是「MD 档 720 / LG 档 840」的硬上限，屏再宽也就到 840 为止，平板横屏中间一条
 * 窄列像邮票，所以同步改成随宽度缓增。
 *
 * 传 0 / 负数（还没量到宽度）时返回 0，调用方按 `100%` 处理，不做约束。
 */
export function readableColumnWidth(availableWidth: number): number {
  if (!(availableWidth > 0)) {
    return 0;
  }
  if (availableWidth <= READABLE_BASE_WIDTH) {
    return availableWidth;
  }
  const scaled: number = availableWidth * READABLE_SCALE;
  return Math.min(availableWidth, Math.max(READABLE_BASE_WIDTH, scaled));
}

/**
 * 浮层控件列宽（vp）：比正文列再窄两侧各 {@link FLOAT_INSET}。
 * 屏幕上没有富余（手机）时直接等于可用宽，不缩。
 */
export function floatingColumnWidth(availableWidth: number): number {
  const column: number = readableColumnWidth(availableWidth);
  if (column <= 0 || column >= availableWidth) {
    return column;
  }
  return Math.max(0, column - 2 * FLOAT_INSET);
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
