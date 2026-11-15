/**
 * 骨架占位页（阶段 0）—— 只验证「工程可构建、Ability 可拉起、资源引用可用」。
 *
 * 阶段 2 会被真正的连接页（对照 app/lib/ui/connect_page.dart）替换；
 * 文案与配色全部走 resources（AGENTS.md §4 token 纪律的鸿蒙侧对应物：
 * 颜色一律 $r('app.color.*')，dark/ 目录已备深色档）。
 * 蓝色 #3964FE 取自 docs/design-tokens.md 的 DsColors.primary —— 设计 token
 * 单一来源仍是那份文档，鸿蒙侧资源文件是它的映射层。
 */
@Entry
@Component
struct Index {
  build() {
    Column({ space: 14 }) {
      Text($r('app.string.skeleton_title'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      Text($r('app.string.skeleton_badge'))
        .fontSize(12)
        .fontColor($r('app.color.brand_primary'))
        .backgroundColor($r('app.color.badge_bg'))
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(999)

      Text($r('app.string.skeleton_body'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.page_bg'))
  }
}
