/**
 * 任务条（安卓 app/lib/ui/todo_dock.dart 口径）—— 挂在 composer 上方。
 * 摘要在 core/TodoDock.ts（node 直测），本组件只渲染与展开。
 */

import { ChatStore } from '../core/ChatStore';
import { TodoItem, todoItems } from '../core/Projections';
import { TodoDockSummary, todoGlyph } from '../core/TodoDock';
import { DsColors, DsSpacing, DsTypography } from '../ui/theme';

@Component
export struct TodoDock {
  store: ChatStore | null = null;
  @Prop @Watch('sync') version: number = 0;
  @State todos: TodoItem[] = [];
  @State expanded: boolean = false;
  @StorageProp('dshDark') dark: boolean = false;

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  aboutToAppear(): void {
    this.sync();
  }

  private sync(): void {
    const st: ChatStore | null = this.store;
    this.todos = st === null ? [] : todoItems(st.projections);
    if (this.todos.length === 0) {
      this.expanded = false;
    }
  }

  build() {
    Column() {
      if (this.summary() !== null) {
      Column() {
        Row() {
          Text('☰')
            .fontSize(14)
            .fontColor(this.c().labelSecondary)
            .accessibilityGroup(true)
          Text((this.summary() as TodoDockSummary).headline)
            .fontSize(DsTypography.small.size)
            .lineHeight(DsTypography.small.lineHeight)
            .fontColor(this.c().labelPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: 8 })
          Text((this.summary() as TodoDockSummary).done.toString() + '/'
            + (this.summary() as TodoDockSummary).total.toString())
            .fontSize(DsTypography.caption.size)
            .fontColor(this.c().labelTertiary)
          Text(this.expanded ? '⌃' : '⌄')
            .fontSize(DsTypography.small.size)
            .fontColor(this.c().labelTertiary)
            .width(40)
            .height(40)
            .textAlign(TextAlign.Center)
            .accessibilityText(this.expanded ? '收起任务' : '展开任务')
        }
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 4 })
        .onClick((): void => {
          this.expanded = !this.expanded;
        })

        Progress({
          value: (this.summary() as TodoDockSummary).done,
          total: (this.summary() as TodoDockSummary).total,
          type: ProgressType.Linear
        })
          .width('100%')
          .height(2)
          .color(this.c().brand)
          .backgroundColor(this.c().borderL1)

        if (this.expanded) {
          Scroll() {
            Column() {
              ForEach(this.todos, (t: TodoItem, i: number) => {
                Row() {
                  Text(todoGlyph(t.status))
                    .fontSize(16)
                    .fontColor(t.status === 'completed' ? this.c().diffAddFg
                      : (t.status === 'in_progress' ? this.c().brand : this.c().labelTertiary))
                    .width(40)
                    .height(40)
                    .textAlign(TextAlign.Center)
                  Text(t.content)
                    .fontSize(DsTypography.small.size)
                    .lineHeight(DsTypography.small.lineHeight)
                    .fontWeight(t.status === 'in_progress' ? FontWeight.Medium : FontWeight.Normal)
                    .fontColor(t.status === 'completed' ? this.c().labelTertiary : this.c().labelPrimary)
                    .layoutWeight(1)
                }
                .width('100%')
                .height(40)
              }, (t: TodoItem, i: number) => i.toString() + '|' + t.content)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 4, right: 12, bottom: 6 })
          }
          .constraintSize({ maxHeight: 168 })
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(this.c().bgLayer1)
      .borderRadius(DsSpacing.settingsCardRadius)
      .borderWidth(1)
      .borderColor(this.c().borderL2)
      .clip(true)
      .margin({ left: 12, right: 12, top: 16 })
      }
    }
    .width('100%')
  }

  private summary(): TodoDockSummary | null {
    const st: ChatStore | null = this.store;
    return TodoDockSummary.of(this.todos, st !== null && st.streaming);
  }
}
