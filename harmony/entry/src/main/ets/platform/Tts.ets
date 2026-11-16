/**
 * 系统 TTS（朗读）—— 安卓 DshPlatform.speak 的鸿蒙对应物。
 *
 * CoreSpeechKit textToSpeech：createEngine → setListener → speak。
 * SDK 约束：**setListener 必须先于 speak**，否则 onStart/onComplete/onError 一律收不到；
 * CreateEngineParams.online 是 0=在线、1=离线（这里取在线，音色更自然）。
 * 失败回 false（UI 提示「朗读暂不可用」，不留死交互，安卓口径）。
 */

import { common } from '@kit.AbilityKit';
import { textToSpeech } from '@kit.CoreSpeechKit';

let engine: textToSpeech.TextToSpeechEngine | null = null;
/** 当前朗读的 requestId；用于忽略过期的完成回调。 */
let currentRequestId: string = '';
/**
 * 朗读状态观察者（UI 用来切「朗读中/朗读」图标）。
 * 用**多观察者列表**而不是单个槽位：聊天页每条助手消息都挂一个 MessageActions，
 * 单槽位会被最后挂载的那个覆盖，其余实例的图标永远不复位。
 */
const busyWatchers: ((busy: boolean) => void)[] = [];

/** 注册观察者。 */
export function addSpeakingWatcher(watcher: (busy: boolean) => void): void {
  if (busyWatchers.indexOf(watcher) < 0) {
    busyWatchers.push(watcher);
  }
}

/** 注销观察者（组件 aboutToDisappear 时调，避免泄漏与悬空回调）。 */
export function removeSpeakingWatcher(watcher: (busy: boolean) => void): void {
  const i: number = busyWatchers.indexOf(watcher);
  if (i >= 0) {
    busyWatchers.splice(i, 1);
  }
}

function notifyBusy(busy: boolean): void {
  // 回调里可能有人注销自己，先拷一份再遍历。
  const snapshot: ((busy: boolean) => void)[] = busyWatchers.slice();
  for (const w of snapshot) {
    w(busy);
  }
}

/** 首次朗读时建引擎并装监听；之后复用。 */
async function ensureEngine(requestId: string): Promise<textToSpeech.TextToSpeechEngine> {
  if (engine !== null) {
    return engine;
  }
  const params: textToSpeech.CreateEngineParams = {
    language: 'zh-CN',
    person: 0,
    online: 0
  };
  const eng: textToSpeech.TextToSpeechEngine = await textToSpeech.createEngine(params);
  const listener: textToSpeech.SpeakListener = {
    onStart: (rid: string, response: textToSpeech.StartResponse): void => {
      if (rid === currentRequestId) {
        notifyBusy(true);
      }
    },
    onComplete: (rid: string, response: textToSpeech.CompleteResponse): void => {
      if (rid === currentRequestId) {
        currentRequestId = '';
        notifyBusy(false);
      }
    },
    onStop: (rid: string, response: textToSpeech.StopResponse): void => {
      if (rid === currentRequestId) {
        currentRequestId = '';
        notifyBusy(false);
      }
    },
    onError: (rid: string, errorCode: number, errorMessage: string): void => {
      if (rid === currentRequestId) {
        currentRequestId = '';
        notifyBusy(false);
      }
    }
  };
  eng.setListener(listener);
  engine = eng;
  return eng;
}

/** 朗读一段文本；true=已开始，false=平台不可用或失败。 */
export async function speak(context: common.UIAbilityContext, text: string): Promise<boolean> {
  const trimmed: string = text.trim();
  if (trimmed.length === 0) {
    return false;
  }
  const requestId: string = 'dsh-' + Date.now().toString();
  try {
    const eng: textToSpeech.TextToSpeechEngine = await ensureEngine(requestId);
    currentRequestId = requestId;
    const extra: Record<string, Object> = {
      'volume': 2.0,
      'speed': 1.0,
      'pitch': 1.0
    } as Record<string, Object>;
    const info: textToSpeech.SpeakParams = {
      requestId: requestId,
      extraParams: extra
    };
    eng.speak(trimmed, info);
    return true;
  } catch (err) {
    currentRequestId = '';
    return false;
  }
}

/** 是否正在朗读。 */
export function isSpeaking(): boolean {
  const e: textToSpeech.TextToSpeechEngine | null = engine;
  if (e === null) {
    return false;
  }
  try {
    return e.isBusy();
  } catch (err) {
    return false;
  }
}

/** 停止朗读（忽略失败）。 */
export function stopSpeak(): void {
  const e: textToSpeech.TextToSpeechEngine | null = engine;
  currentRequestId = '';
  if (e === null) {
    return;
  }
  try {
    e.stop();
  } catch (err) {
    // 忽略
  }
  notifyBusy(false);
}

/** 释放引擎（Ability 销毁时调用，避免长期占音频焦点）。 */
export function shutdownTts(): void {
  const e: textToSpeech.TextToSpeechEngine | null = engine;
  engine = null;
  currentRequestId = '';
  busyWatchers.length = 0;
  if (e === null) {
    return;
  }
  try {
    e.shutdown();
  } catch (err) {
    // 忽略
  }
}
