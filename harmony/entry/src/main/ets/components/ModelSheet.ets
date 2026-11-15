/**
 * 模型选择面板 —— 对照安卓 model_sheet.dart：
 * models 帧拉清单 → 分组列表（默认只展开当前供应商）→ pending 三态
 * → select-model 帧切换（应答异常/RequestException 提示）。
 * bindSheet 内容组件，由 ChatView 挂载。
 */

import { ChatStore } from '../core/ChatStore';
import { JsonMap } from '../core/JsonAccess';
import { SessionModels, ModelProviderGroup, ModelView, ModelSelection,
  ModelReasoningEffort, reasoningEffortLabel } from '../core/ModelsView';
import { DsColors, DsTypography, DsSpacing } from '../ui/theme';

@Component
export struct ModelSheet {
  store: ChatStore | null = null;
  @StorageProp('dshDark') dark: boolean = false;
  /** 确认成功后由父层关 sheet（ArkTS @Link 绑不便传，改回调）。 */
  onDone: (() => void) | null = null;
  @State models: SessionModels | null = null;
  @State error: string = '';
  @State pendingProvider: string = '';
  @State pendingModel: string = '';
  @State pendingEffort: string = '';
  /** 展开的供应商 id（默认只展开当前，真机反馈第 4 项）。 */
  @State expanded: string[] = [];
  private loadedSid: string = '';

  private c(): DsColors {
    return new DsColors(this.dark);
  }

  private sid(): string {
    const st: ChatStore | null = this.store;
    return st === null ? '' : (st.sessionId ?? '');
  }

  /** 打开时拉清单（sessionId 变了重拉）。 */
  load(): void {
    const st: ChatStore | null = this.store;
    const sid: string = this.sid();
    if (st === null || sid.length === 0) {
      this.error = '请先打开一个会话再调整模型';
      return;
    }
    if (this.loadedSid === sid && this.models !== null) {
      return;
    }
    this.error = '';
    st.api.sessionModels(st.sessionId ?? '').then((data: JsonMap): void => {
      const m: SessionModels = SessionModels.parse(data);
      this.models = m;
      this.loadedSid = sid;
      this.pendingProvider = m.current.provider;
      this.pendingModel = m.current.model;
      this.pendingEffort = m.current.reasoningEffort ?? '';
      const exp: string[] = [];
      if (m.current.provider.length > 0) {
        exp.push(m.current.provider);
      }
      this.expanded = exp;
    }).catch((): void => {
      this.error = '模型清单获取失败';
    });
  }

  private toggleExpanded(id: string): void {
    const idx: number = this.expanded.indexOf(id);
    if (idx >= 0) {
      const next: string[] = this.expanded.slice();
      next.splice(idx, 1);
      this.expanded = next;
    } else {
      this.expanded = this.expanded.concat([id]);
    }
  }

  private isPending(g: ModelProviderGroup, m: ModelView): boolean {
    return this.pendingProvider === g.id && this.pendingModel === m.id;
  }

  private pick(g: ModelProviderGroup, m: ModelView, effort: string | null): void {
    this.pendingProvider = g.id;
    this.pendingModel = m.id;
    this.pendingEffort = effort === null ? '' : effort;
  }

  private confirm(): void {
    const st: ChatStore | null = this.store;
    if (st === null || this.pendingProvider.length === 0 || this.pendingModel.length === 0) {
      return;
    }
    const effort: string | null = this.pendingEffort.length === 0 ? null : this.pendingEffort;
    st.selectModel(this.pendingProvider, this.pendingModel, effort)
      .then((selected: ModelSelection | null): void => {
        if (selected === null) {
          this.error = '切换失败：服务端应答异常';
          return;
        }
        if (this.onDone !== null) {
          this.onDone();
        }
      }).catch((): void => {
        this.error = '切换失败';
      });
  }

  @Builder
  groupSection(g: ModelProviderGroup) {
    Column() {
      // 分组头（可点收缩）。
      Row() {
        Text(g.name)
          .fontSize(DsTypography.smallStrong.size)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c().labelSecondary)
        Blank()
        Text(this.expanded.indexOf(g.id) >= 0 ? '⌃' : '⌄')
          .fontSize(15)
          .fontColor(this.c().labelTertiary)
      }
      .width('100%')
      .padding({ left: DsSpacing.settingsCardPadH, right: DsSpacing.settingsCardPadH,
        top: 6, bottom: 6 })
      .onClick(() => {
        this.toggleExpanded(g.id);
      })
      if (this.expanded.indexOf(g.id) >= 0) {
        ForEach(g.models, (m: ModelView) => {
          this.modelRow(g, m)
        }, (m: ModelView) => m.id)
      } else if (this.pendingProvider === g.id && this.pendingModel.length > 0) {
        // 折叠组里当前 pending 模型提示一行。
        Text(this.pendingModelName(g))
          .fontSize(DsTypography.small.size)
          .fontColor(this.c().brand)
          .padding({ left: DsSpacing.settingsCardPadH + 6, bottom: 6 })
          .width('100%')
      }
    }
    .width('100%')
  }

  private pendingModelName(g: ModelProviderGroup): string {
    for (const m of g.models) {
      if (m.id === this.pendingModel) {
        return m.name;
      }
    }
    return this.pendingModel;
  }

  @Builder
  modelRow(g: ModelProviderGroup, m: ModelView) {
    Column() {
      Row({ space: 8 }) {
        Text(this.isPending(g, m) ? '✓' : '○')
          .fontSize(16)
          .fontColor(this.isPending(g, m) ? this.c().brand : this.c().labelTertiary)
        Text(m.name)
          .fontSize(DsTypography.base.size)
          .fontColor(this.c().labelPrimary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: DsSpacing.settingsCardPadH, right: DsSpacing.settingsCardPadH,
        top: 9, bottom: m.reasoning === null ? 9 : 2 })
      .onClick(() => {
        this.pick(g, m, m.reasoning === null ? '' : (m.reasoning.defaultEffort ?? ''));
      })
      // 推理档位 ChoiceChips。
      if (m.reasoning !== null && m.reasoning.efforts.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(m.reasoning.efforts, (e: ModelReasoningEffort) => {
            Text(reasoningEffortLabel(e.id))
              .fontSize(DsTypography.caption.size)
              .margin({ right: 6, bottom: 4 })
              .fontColor(this.isPending(g, m) && this.pendingEffort === e.id
                ? this.c().chipSelectedFg : this.c().labelSecondary)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(DsSpacing.chipRadius)
              .backgroundColor(this.isPending(g, m) && this.pendingEffort === e.id
                ? this.c().chipSelectedBg : this.c().inputFill)
              .onClick(() => {
                this.pick(g, m, e.id);
              })
          }, (e: ModelReasoningEffort) => e.id)
        }
        .width('100%')
        .padding({ left: DsSpacing.settingsCardPadH + 24, right: DsSpacing.settingsCardPadH,
          bottom: 8 })
      }
    }
    .width('100%')
  }

  build() {
    Column() {
      Row() {
        Text('调整模型')
          .fontSize(DsTypography.baseStrong.size)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c().labelPrimary)
        Blank()
        if (this.models !== null && (!this.models.routable || this.models.failures.length > 0)) {
          Text('⚠')
            .fontSize(16)
            .fontColor(this.c().settingsWarnFg)
        }
      }
      .width('100%')
      .padding(DsSpacing.settingsCardPadH)
      Scroll() {
        Column() {
          if (this.error.length > 0) {
            Text(this.error)
              .fontSize(DsTypography.small.size)
              .fontColor(this.c().danger)
              .padding(DsSpacing.settingsCardPadH)
          } else if (this.models === null) {
            Text('加载中…')
              .fontSize(DsTypography.small.size)
              .fontColor(this.c().labelSecondary)
              .padding(DsSpacing.settingsCardPadH)
          } else {
            ForEach(this.models.groups, (g: ModelProviderGroup) => {
              this.groupSection(g)
            }, (g: ModelProviderGroup) => g.id)
            if (this.models !== null && this.models.failures.length > 0) {
              Text('以下服务暂不可用：' + this.failureNames())
                .fontSize(DsTypography.small.size)
                .fontColor(this.c().settingsWarnFg)
                .padding(DsSpacing.settingsCardPadH)
            }
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      Button('确认切换')
        .width('100%')
        .height(48)
        .backgroundColor(this.c().brand)
        .fontColor(this.c().onBrand)
        .fontSize(DsTypography.baseStrong.size)
        .enabled(this.pendingProvider.length > 0 && this.pendingModel.length > 0)
        .margin(DsSpacing.settingsCardPadH)
        .onClick(() => {
          this.confirm();
        })
    }
    .width('100%')
    .backgroundColor(this.c().bgLayer1)
    .borderRadius({ topLeft: DsSpacing.settingsCardRadius, topRight: DsSpacing.settingsCardRadius })
  }

  private failureNames(): string {
    const st: SessionModels | null = this.models;
    if (st === null) {
      return '';
    }
    const names: string[] = [];
    for (const f of st.failures) {
      names.push(f.provider);
    }
    return names.join('、');
  }
}

