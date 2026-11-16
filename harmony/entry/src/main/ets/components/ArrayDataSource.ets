/**
 * LazyForEach 数据源（R005）：把「整体替换」语义的数组包装成 `IDataSource`。
 *
 * 为什么不做逐项 diff：`ChatStore.messages` 每次 changed() 都是新数组，消息条目本身
 * 不可变（流式是替换整条 ChatMessage），逐项 diff 拿不到收益，反而要写一堆
 * ChatMessage 相等性判断。所以 `reset(items)` 直接 `onDataReloaded()`。
 *
 * 唯一要注意的是 **key 必须稳定**：`LazyForEach` 靠 keyGenerator 的返回值判断复用，
 * key 一变就重建子组件。消息列表的 key 用 `role + seq + 文本长度`（seq 是服务端序号，
 * 翻页 prepend 时老消息的 seq 不变）；会话列表的 key 带上 `earlierOpen`，这样展开/收起
 * 时能强制重建分组项，让内层 rowsOf 重算。
 */

/** 与 SDK 的 IDataSource 接口一致（DataChangeListener 是 ArkUI 全局声明）。 */
export class ArrayDataSource<T> implements IDataSource {
  private items: T[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(items: T[]) {
    this.items = items;
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): T {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx: number = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  /** 换整批数据：数量或内容都可能全变，用全量 reload（最省心也最不丢更新）。 */
  reset(items: T[]): void {
    this.items = items;
    const n: number = this.listeners.length;
    for (let i = 0; i < n; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}
