import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, KeyboardAvoidMode } from '@kit.ArkUI';
import { PrefsStore } from '../platform/PlatformBridge';
import { shutdownTts } from '../platform/Tts';

const DOMAIN: number = 0x0000;
const TAG: string = 'DshChat';

/**
 * 鸿蒙版唯一 Ability。
 *
 * 深浅色**跟随系统**：`onCreate` 里显式 `setColorMode(COLOR_MODE_NOT_SET)`。
 * 这行不能省 —— 不显式声明时应用会停在启动那一刻的 colorMode 上，用户在后台切深色
 * 后回来整屏仍是白底（姊妹仓 PORT-MAP 坑 20 的真机教训，骨架阶段就做对）。
 * 系统色模式同时写入 AppStorage('dshDark')，主题层据此选亮/暗 token。
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onCreate');
    this.bindColorMode();
    PrefsStore.init(this.context);
  }

  private bindColorMode(): void {
    try {
      const appContext = this.context.getApplicationContext();
      appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'setColorMode failed: %{public}s', JSON.stringify(err));
    }
    // 初始深浅色：ApplicationConfig 无 getConfig（本 SDK 实测），
    // 用主窗口 colorMode 在 onWindowStageCreate 读；先按浅色起步，
    // onConfigurationUpdate 随系统切换持续纠偏。
    AppStorage.setOrCreate('dshDark', false);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    AppStorage.setOrCreate('dshDark',
      newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onDestroy');
    // 释放 TTS 引擎：CoreSpeechKit 的引擎是进程级单例，不 shutdown 会一直占着
    // 音频焦点（下次朗读报忙/无声）。
    shutdownTts();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      // 键盘避让：默认 OFFSET 会整页上移，底部输入框连带被推出/压住（真机实证）。
      // RESIZE 压缩页面高度，Column(height 100%) 的聊天页随之收缩，composer 停在
      // 键盘上沿；List 的 layoutWeight 吃掉多余空间。必须在 loadContent 之后拿
      // UIContext（在此之前还没有 UI 实例）。
      try {
        windowStage.getMainWindowSync().getUIContext()
          .setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      } catch (e) {
        const err = e as BusinessError;
        hilog.warn(DOMAIN, TAG, 'setKeyboardAvoidMode failed: %{public}s', JSON.stringify(err));
      }
      hilog.info(DOMAIN, TAG, 'loadContent succeeded');
    });
  }
}
