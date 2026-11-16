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
/** 最近一次失败原因（内部诊断用；空=无错）。 */
let lastTtsError: string = '';

/** 最近一次建引擎/朗读失败的原因（排障用；成功时为空串）。 */
export function ttsLastError(): string {
  return lastTtsError;
}
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

/**
 * 建引擎候选参数（真机实证）：`{language:'zh-CN', person:0, online:0}` 报
 * 1002300005 create engine failed；带 `extraParams.style/locate/name` 报 202
 * this is not systemCap（extraParams 里有未声明的 key 全校验失败）。
 * 目前已知可行形态是最小参数 + person 换值，逐个试，首个成功即用。
 */
function probeParams(): textToSpeech.CreateEngineParams[] {
  const out: textToSpeech.CreateEngineParams[] = [];
  out.push({ language: 'zh-CN', person: 0, online: 1 });
  out.push({ language: 'zh-CN', person: 1, online: 1 });
  out.push({ language: 'zh-CN', person: 0, online: 0 });
  out.push({ language: 'zh-CN', person: 1, online: 0 });
  out.push({ language: 'en-US', person: 0, online: 0 });
  return out;
}

/** 首次朗读时建引擎并装监听；之后复用。 */
async function ensureEngine(requestId: string): Promise<textToSpeech.TextToSpeechEngine> {
  if (engine !== null) {
    return engine;
  }
  // 建引擎参数探测：真机对不同组合反应不同（1002300005 create failed / 202 校验失败），
  // 依次试 (online, person) 组合，第一个成功的缓存下来。
  const attempts: textToSpeech.CreateEngineParams[] = probeParams();
  let eng: textToSpeech.TextToSpeechEngine | null = null;
  let lastErr: string = '';
  for (const params of attempts) {
    try {
      eng = await textToSpeech.createEngine(params);
      break;
    } catch (e) {
      lastErr = JSON.stringify(e);
      eng = null;
    }
  }
  if (eng === null) {
    throw new Error('create engine failed: ' + lastErr);
  }
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
  lastTtsError = '';
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
    lastTtsError = 'ERR:' + JSON.stringify(err);
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
