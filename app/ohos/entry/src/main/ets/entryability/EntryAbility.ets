/**
 * 鸿蒙宿主 Ability（Flutter-OH）。
 *
 * 职责：
 * 1. 注册 Flutter 自动生成的插件（GeneratedPluginRegistrant）；
 * 2. 注册三个自研通道插件：dsh/device、dsh/platform、dsh/notify；
 * 3. 把通知点击的 Want 交给 DshNotifyPlugin（冷启动 onCreate + 运行期 onNewWant）；
 * 4. 退出时释放 TTS 引擎，避免长期占音频焦点。
 *
 * 注意：configureFlutterEngine 被调用时引擎已 attachToAbility（见
 * FlutterAbilityAndEntryDelegate.onAttach），所以这里 add 的 AbilityAware
 * 插件会立即拿到 UIAbilityContext。
 */

import { AbilityConstant, Want } from '@kit.AbilityKit';
import { FlutterAbility, FlutterEngine, PluginRegistry } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import DshDevicePlugin from '../plugins/DshDevicePlugin';
import DshPlatformPlugin from '../plugins/DshPlatformPlugin';
import DshNotifyPlugin from '../plugins/DshNotifyPlugin';
import { shutdownTts } from '../platform/Tts';

export default class EntryAbility extends FlutterAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onCreate(want, launchParam);
    // 冷启动若由通知点击拉起，先把载荷暂存，等 Dart 侧 takeLaunchTap 取。
    DshNotifyPlugin.stashLaunchWant(want);
  }

  configureFlutterEngine(flutterEngine: FlutterEngine): void {
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);
    const registry: PluginRegistry | null = flutterEngine.getPlugins();
    if (registry !== null) {
      registry.add(new DshDevicePlugin());
      registry.add(new DshPlatformPlugin());
      registry.add(new DshNotifyPlugin());
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParam);
    // App 已在运行时的通知点击：直接回推 tap。
    DshNotifyPlugin.handleWant(want);
  }

  onDestroy(): void {
    shutdownTts();
    super.onDestroy();
  }
}
