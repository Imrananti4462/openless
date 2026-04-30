// i18n 入口 — 必须在任意 UI 组件 import 之前完成 init。
//
// 设计说明：
// - 资源在打包时静态注入（zh-CN.ts / en.ts）。无需后端推送，无网络请求。
// - LocalStorage key `ol.locale` 持久化用户选择；首次启动按 navigator.language 推断。
// - fallback 永远是 zh-CN：已知的产品权威文案，且 zh-CN.ts 是 source of truth。

import i18n from 'i18next';
import LanguageDetector from 'i18next-browser-languagedetector';
import { initReactI18next } from 'react-i18next';
import { en } from './en';
import { zhCN } from './zh-CN';

export const SUPPORTED_LOCALES = ['zh-CN', 'en'] as const;
export type SupportedLocale = (typeof SUPPORTED_LOCALES)[number];

export const LOCALE_STORAGE_KEY = 'ol.locale';
const FOLLOW_SYSTEM_VALUE = 'system';

void i18n
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    resources: {
      'zh-CN': { translation: zhCN },
      en: { translation: en },
    },
    fallbackLng: 'zh-CN',
    supportedLngs: SUPPORTED_LOCALES as unknown as string[],
    nonExplicitSupportedLngs: true, // 'zh' / 'zh-Hans' 等都收敛到 'zh-CN'
    load: 'currentOnly',
    interpolation: { escapeValue: false },
    detection: {
      order: ['localStorage', 'navigator'],
      lookupLocalStorage: LOCALE_STORAGE_KEY,
      caches: ['localStorage'],
    },
  });

export default i18n;

/**
 * 当前持久化偏好。'system' 表示跟随系统；具体语言 tag 表示用户已显式选择。
 * 与 i18n.language 不同：i18n.language 永远是已 resolve 的具体语言。
 */
export function getLocalePreference(): SupportedLocale | typeof FOLLOW_SYSTEM_VALUE {
  if (typeof window === 'undefined') return FOLLOW_SYSTEM_VALUE;
  const raw = window.localStorage.getItem(LOCALE_STORAGE_KEY);
  if (raw === 'zh-CN' || raw === 'en') return raw;
  return FOLLOW_SYSTEM_VALUE;
}

/**
 * 写入用户偏好并立即切换 i18n 语言。
 * pref === 'system' 时清除存储项，让下次启动重新走 navigator 检测。
 */
export async function setLocalePreference(pref: SupportedLocale | typeof FOLLOW_SYSTEM_VALUE): Promise<void> {
  if (pref === FOLLOW_SYSTEM_VALUE) {
    window.localStorage.removeItem(LOCALE_STORAGE_KEY);
    const detected = (i18n.services.languageDetector?.detect?.() as string | string[] | undefined) ?? 'zh-CN';
    const target = Array.isArray(detected) ? detected[0] : detected;
    await i18n.changeLanguage(target);
    return;
  }
  await i18n.changeLanguage(pref);
}

export const FOLLOW_SYSTEM = FOLLOW_SYSTEM_VALUE;
