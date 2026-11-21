/**
 * 轮级卡片装配（改动卡 + 生成文件卡）。
 *
 * 挂在 MessageList 的 assistant 分支里、TurnProcessRow 之后；由 core/TurnCards
 * 判定「闭合轮的最后一条 assistant」并给出数据，本组件只负责渲染与打开 diff 页。
 * diff 页用本节点的 bindContentCover 承载（MessageList 根节点已有文档查看器的
 * cover，按「一个节点一个 cover」的坑位纪律分开挂）。
 */

import { ChatStore } from '../core/ChatStore';
import { ChatMessage } from '../core/HistoryPage';
import { TurnCards as TurnCardsData, turnCardsOf } from '../core/TurnCards';
import { ArtifactFile, FileChange } from '../core/TurnChanges';
import { ChangeCard } from './ChangeCard';
import { ArtifactCard } from './ArtifactCard';
import { ChangeDiffPage } from '../pages/ChangeDiffPage';

@Component
export struct TurnCards {
  store: ChatStore | null = null;
  msg: ChatMessage | null = null;
  @Prop @Watch('syncVersion') version: number = 0;
  @State hasChanges: boolean = false;
  @State hasArtifacts: boolean = false;
  @State files: FileChange[] = [];
  @State artifacts: ArtifactFile[] = [];
  @State diffOpen: boolean = false;
  @State diffIndex: number = 0;

  aboutToAppear(): void {
    this.syncVersion();
  }

  private syncVersion(): void {
    const st: ChatStore | null = this.store;
    const m: ChatMessage | null = this.msg;
    if (st === null || m === null) {
      this.hasChanges = false;
      this.hasArtifacts = false;
      return;
    }
    let index: number = -1;
    for (let i = 0; i < st.messages.length; i++) {
      if (st.messages[i] === m) {
        index = i;
        break;
      }
    }
    const cards: TurnCardsData | null = index < 0 ? null : turnCardsOf(st.messages, index, st.streaming);
    if (cards === null) {
      this.hasChanges = false;
      this.hasArtifacts = false;
      this.files = [];
      this.artifacts = [];
      return;
    }
    this.hasChanges = cards.hasChanges() && cards.changes !== null;
    this.files = cards.changes === null ? [] : cards.changes.files;
    // 生成卡的数据（ArtifactFile[]）在子组件里按 @Prop 收：这里只存数量触发重建，
    // 实际数组随 version 经 store 再取（见 artifactsOf）。
    this.hasArtifacts = cards.hasArtifacts();
    this.artifacts = cards.artifacts;
  }

  @Builder
  diffView() {
    ChangeDiffPage({
      sessionId: '',
      files: this.files,
      initialIndex: this.diffIndex,
      onBack: (): void => {
        this.diffOpen = false;
      }
    })
  }

  build() {
    Column() {
      if (this.hasChanges) {
        ChangeCard({
          files: this.files,
          onOpen: (index: number): void => {
            if (this.files.length === 0) {
              return;
            }
            this.diffIndex = index;
            this.diffOpen = true;
          }
        })
      }
      if (this.hasArtifacts) {
        ArtifactCard({ files: this.artifacts })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .bindContentCover(this.diffOpen, this.diffView(), {
      modalTransition: ModalTransition.DEFAULT,
      onDisappear: (): void => {
        this.diffOpen = false;
      }
    })
  }
}
