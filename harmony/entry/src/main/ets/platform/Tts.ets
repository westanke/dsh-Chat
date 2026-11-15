/**
 * 系统 TTS（朗读）—— 安卓 DshPlatform.speak 的鸿蒙对应物。
 * CoreSpeechKit textToSpeech：createEngine → speak。失败回 false
 * （UI 提示「朗读暂不可用」，不留死交互，安卓口径）。
 */

import { common } from '@kit.AbilityKit';
import { textToSpeech } from '@kit.CoreSpeechKit';

let engine: textToSpeech.TextToSpeechEngine | null = null;

async function ensureEngine(): Promise<textToSpeech.TextToSpeechEngine> {
  if (engine !== null) {
    return engine;
  }
  const params: textToSpeech.CreateEngineParams = {
    language: 'zh-CN',
    person: 0,
    online: 1
  };
  const eng: textToSpeech.TextToSpeechEngine = await textToSpeech.createEngine(params);
  engine = eng;
  return eng;
}

/** 朗读一段文本；true=已开始，false=平台不可用或失败。 */
export async function speak(context: common.UIAbilityContext, text: string): Promise<boolean> {
  const trimmed: string = text.trim();
  if (trimmed.length === 0) {
    return false;
  }
  try {
    const eng: textToSpeech.TextToSpeechEngine = await ensureEngine();
    const extra: Record<string, Object> = {
      'volume': 2.0,
      'speed': 1.0,
      'pitch': 1.0
    } as Record<string, Object>;
    const info: textToSpeech.SpeakParams = {
      requestId: 'dsh-' + Date.now().toString(),
      extraParams: extra
    };
    eng.speak(trimmed, info);
    return true;
  } catch (err) {
    return false;
  }
}

/** 停止朗读（忽略失败）。 */
export function stopSpeak(): void {
  if (engine === null) {
    return;
  }
  try {
    engine.stop();
  } catch (err) {
    // 忽略
  }
}
