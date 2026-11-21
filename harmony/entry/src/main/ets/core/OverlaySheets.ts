/**
 * 会话页浮层（bindSheet）的判定与标题（纯逻辑）。
 *
 * 从 `pages/ChatView.ets` 抽出来，一是守住「单文件 ≤500 行」的工程纪律，
 * 二是让「哪个浮层开着 / 它叫什么」可以被 node 直测（core 层禁 import @kit）。
 * 七个布尔与七个标题是一一对应的，顺序即优先级：同时开两个时取先命中的那个
 * （正常交互下不会同时开，这里只是兜底）。
 */
export interface SheetFlags {
  stats: boolean;
  trajectory: boolean;
  team: boolean;
  todo: boolean;
  model: boolean;
  loc: boolean;
  codeWork: boolean;
}

/** 有没有任何一个浮层开着（决定 bindSheet 的 bind 值）。 */
export function sheetOpenOf(flags: SheetFlags): boolean {
  return flags.stats || flags.trajectory || flags.team || flags.todo
    || flags.model || flags.loc || flags.codeWork;
}

/** 当前浮层的标题；都没开就空串（与 sheetOpenOf 同口径）。 */
export function sheetTitleOf(flags: SheetFlags): string {
  if (flags.stats) {
    return '会话统计';
  }
  if (flags.trajectory) {
    return '运行轨迹';
  }
  if (flags.team) {
    return '智能团队';
  }
  if (flags.todo) {
    return '任务';
  }
  if (flags.model) {
    return '调整模型';
  }
  if (flags.loc) {
    return '会话工作目录';
  }
  if (flags.codeWork) {
    return '代码工作视图';
  }
  return '';
}
