import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { getHotkeyCapability, getSettings, setSettings } from '../lib/ipc';
import type { HotkeyBinding, HotkeyCapability, UserPreferences } from '../lib/types';
import i18n from '../i18n';

interface HotkeySettingsContextValue {
  prefs: UserPreferences | null;
  hotkey: HotkeyBinding | null;
  capability: HotkeyCapability | null;
  loading: boolean;
  refresh: () => Promise<void>;
  updatePrefs: (next: UserPreferences) => Promise<void>;
}

const HotkeySettingsContext = createContext<HotkeySettingsContextValue | null>(null);

export function HotkeySettingsProvider({ children }: { children: ReactNode }) {
  const [prefs, setPrefs] = useState<UserPreferences | null>(null);
  const [capability, setCapability] = useState<HotkeyCapability | null>(null);
  const [loading, setLoading] = useState(true);
  const syncSeqRef = useRef(0);
  const persistQueueRef = useRef<Promise<void>>(Promise.resolve());
  const latestPrefsRef = useRef<UserPreferences | null>(null);

  const refresh = useCallback(async () => {
    const [nextPrefs, nextCapability] = await Promise.all([getSettings(), getHotkeyCapability()]);
    setPrefs(nextPrefs);
    setCapability(nextCapability);
    setLoading(false);
  }, []);

  const queueSetSettings = useCallback((next: UserPreferences) => {
    const task = persistQueueRef.current
      .catch(() => undefined)
      .then(() => setSettings(next));
    persistQueueRef.current = task;
    return task;
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    latestPrefsRef.current = prefs;
  }, [prefs]);

  useEffect(() => {
    const currentPrefs = latestPrefsRef.current;
    if (!currentPrefs) return;
    const lang = (i18n.resolvedLanguage || i18n.language || '').toLowerCase();
    const nextScript: UserPreferences['chineseScriptPreference'] =
      lang.startsWith('zh-tw') || lang.includes('hant')
        ? 'traditional'
        : lang.startsWith('zh-cn') || lang.startsWith('zh')
          ? 'simplified'
          : 'auto';
    if (currentPrefs.chineseScriptPreference === nextScript) return;
    const previousScript = currentPrefs.chineseScriptPreference;
    const next = { ...currentPrefs, chineseScriptPreference: nextScript };
    const seq = ++syncSeqRef.current;
    void queueSetSettings(next)
      .then(() => {
        setPrefs(current => {
          if (!current || syncSeqRef.current !== seq) return current;
          if (current.chineseScriptPreference !== previousScript) return current;
          return { ...current, chineseScriptPreference: nextScript };
        });
      })
      .catch(error => {
        if (syncSeqRef.current === seq) {
          console.warn('[settings] sync chineseScriptPreference failed', error);
        }
      });
  }, [prefs, queueSetSettings]);

  const updatePrefs = useCallback(async (next: UserPreferences) => {
    setPrefs(next);
    latestPrefsRef.current = next;
    await queueSetSettings(next);
  }, [queueSetSettings]);

  const value = useMemo<HotkeySettingsContextValue>(
    () => ({
      prefs,
      hotkey: prefs?.hotkey ?? null,
      capability,
      loading,
      refresh,
      updatePrefs,
    }),
    [capability, loading, prefs, refresh, updatePrefs],
  );

  return <HotkeySettingsContext.Provider value={value}>{children}</HotkeySettingsContext.Provider>;
}

export function useHotkeySettings() {
  const value = useContext(HotkeySettingsContext);
  if (!value) {
    throw new Error('useHotkeySettings must be used within HotkeySettingsProvider');
  }
  return value;
}
