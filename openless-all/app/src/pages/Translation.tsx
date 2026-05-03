// Translation.tsx — 独立的"翻译"页，从 Settings → 录音 中拆出来。
// 用户在这里：
//   - 勾选自己的工作语言（多选，用作 LLM polish/translate prompt 的前提）
//   - 选一个翻译目标语言（单选；选"不启用"则 Shift 不触发翻译）
//   - 看完整使用说明（怎么触发、按钮位置、胶囊显示）

import type { CSSProperties } from 'react';
import { useTranslation } from 'react-i18next';
import { Card, PageHeader, Pill } from './_atoms';
import { SUPPORTED_LANGUAGES } from '../lib/types';
import { useHotkeySettings } from '../state/HotkeySettingsContext';
import { getHotkeyTriggerLabel } from '../lib/hotkey';

export function Translation() {
  const { t } = useTranslation();
  const { prefs, updatePrefs: savePrefs, hotkey } = useHotkeySettings();

  if (!prefs) {
    return (
      <>
        <PageHeader
          kicker={t('translation.kicker')}
          title={t('translation.title')}
          desc={t('translation.desc')}
        />
        <Card>
          <div style={{ fontSize: 12, color: 'var(--ol-ink-4)' }}>{t('common.loading')}</div>
        </Card>
      </>
    );
  }

  const onWorkingLanguagesChange = (workingLanguages: string[]) =>
    savePrefs({ ...prefs, workingLanguages });
  const toggleWorkingLanguage = (lang: string) => {
    const next = prefs.workingLanguages.includes(lang)
      ? prefs.workingLanguages.filter(l => l !== lang)
      : [...prefs.workingLanguages, lang];
    onWorkingLanguagesChange(next);
  };
  const onTargetChange = (translationTargetLanguage: string) =>
    savePrefs({ ...prefs, translationTargetLanguage });

  const triggerLabel = getHotkeyTriggerLabel(hotkey?.trigger);
  const enabled = prefs.translationTargetLanguage.trim() !== '';
  const howtoSteps = [
    t('translation.howto.step1'),
    t('translation.howto.step2', { trigger: triggerLabel }),
    t('translation.howto.step3'),
    t('translation.howto.step4'),
    t('translation.howto.step5'),
  ];

  return (
    <>
      <PageHeader
        kicker={t('translation.kicker')}
        title={t('translation.title')}
        desc={t('translation.desc')}
      />

      <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        {/* 1. 翻译目标语言 */}
        <Card>
          <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0, 1fr) 220px', gap: 18, alignItems: 'stretch' }}>
            <div>
              <div style={settingsHeaderStyle}>
                <div style={settingsTitleStyle}>{t('translation.target.title')}</div>
                <Pill tone={enabled ? 'blue' : 'outline'} size="sm">
                  {enabled ? t('translation.statusEnabled') : t('translation.statusDisabled')}
                </Pill>
              </div>
              <div style={settingsDescStyle}>{t('translation.target.desc')}</div>
              <select
                value={prefs.translationTargetLanguage}
                onChange={e => onTargetChange(e.target.value)}
                style={selectStyle}
              >
                <option value="">{t('translation.target.disabled')}</option>
                {SUPPORTED_LANGUAGES.map(lang => (
                  <option key={lang} value={lang}>{lang}</option>
                ))}
              </select>
            </div>

            <div style={translationStatusStyle(enabled)}>
              <div style={{ fontSize: 11, color: enabled ? 'var(--ol-blue)' : 'var(--ol-ink-4)', fontWeight: 600, letterSpacing: '0.06em', textTransform: 'uppercase' }}>
                {enabled ? t('translation.statusEnabled') : t('translation.statusDisabled')}
              </div>
              <div style={{ marginTop: 10, fontSize: 22, lineHeight: 1.1, fontWeight: 650, letterSpacing: '-0.03em', color: enabled ? 'var(--ol-blue)' : 'var(--ol-ink-2)' }}>
                {enabled ? prefs.translationTargetLanguage : t('translation.statusDisabled')}
              </div>
              <div style={{ marginTop: 8, fontSize: 11.5, color: 'var(--ol-ink-4)', lineHeight: 1.5 }}>
                Shift
              </div>
            </div>
          </div>
        </Card>

        {/* 2. 工作语言 */}
        <Card>
          <div style={settingsTitleStyle}>{t('translation.working.title')}</div>
          <div style={settingsDescStyle}>{t('translation.working.desc')}</div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7 }}>
            {SUPPORTED_LANGUAGES.map(lang => {
              const checked = prefs.workingLanguages.includes(lang);
              return (
                <button
                  key={lang}
                  onClick={() => toggleWorkingLanguage(lang)}
                  style={languageChipStyle(checked)}
                >
                  {lang}
                </button>
              );
            })}
          </div>
        </Card>

        {/* 3. 使用方法 */}
        <Card>
          <div style={settingsTitleStyle}>{t('translation.howto.title')}</div>
          <div style={{ display: 'grid', gap: 8, marginTop: 12 }}>
            {howtoSteps.map((step, index) => (
              <div key={step} style={stepRowStyle}>
                <span style={stepNumberStyle}>{String(index + 1).padStart(2, '0')}</span>
                <span style={{ minWidth: 0 }}>{step}</span>
              </div>
            ))}
          </div>
        </Card>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <InfoTile tone="blue" title={t('translation.howto.indicatorTitle')} body={t('translation.howto.indicatorDesc')} />
          <InfoTile tone="neutral" title={t('translation.howto.fallbackTitle')} body={t('translation.howto.fallbackDesc')} />
        </div>
      </div>
    </>
  );
}

const settingsHeaderStyle: CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  gap: 12,
  marginBottom: 5,
};

const settingsTitleStyle: CSSProperties = {
  fontSize: 13,
  fontWeight: 650,
  color: 'var(--ol-ink)',
};

const settingsDescStyle: CSSProperties = {
  fontSize: 11.5,
  color: 'var(--ol-ink-4)',
  marginBottom: 14,
  lineHeight: 1.58,
};

const selectStyle: CSSProperties = {
  width: '100%',
  maxWidth: 380,
  height: 34,
  padding: '0 11px',
  fontSize: 13,
  border: '0.5px solid var(--ol-line-strong)',
  borderRadius: 9,
  background: '#fff',
  color: 'var(--ol-ink)',
  fontFamily: 'inherit',
  cursor: 'default',
  boxShadow: '0 1px 0 rgba(255,255,255,0.9) inset',
};

const stepRowStyle: CSSProperties = {
  display: 'grid',
  gridTemplateColumns: '34px minmax(0, 1fr)',
  gap: 10,
  alignItems: 'start',
  padding: '9px 10px',
  borderRadius: 11,
  background: 'rgba(0,0,0,0.025)',
  color: 'var(--ol-ink-2)',
  fontSize: 12.5,
  lineHeight: 1.55,
};

const stepNumberStyle: CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
  width: 24,
  height: 24,
  borderRadius: 999,
  background: 'rgba(255,255,255,0.85)',
  color: 'var(--ol-ink-4)',
  fontFamily: 'var(--ol-font-mono)',
  fontSize: 10.5,
  fontWeight: 600,
  boxShadow: '0 1px 2px rgba(0,0,0,0.04), 0 0 0 0.5px var(--ol-line)',
};

function languageChipStyle(checked: boolean): CSSProperties {
  return {
    padding: '6px 12px',
    fontSize: 12.5,
    fontWeight: checked ? 650 : 500,
    border: checked ? '0.5px solid rgba(37,99,235,0.35)' : '0.5px solid var(--ol-line)',
    borderRadius: 999,
    background: checked ? 'var(--ol-blue)' : 'rgba(255,255,255,0.72)',
    color: checked ? '#fff' : 'var(--ol-ink-2)',
    cursor: 'default',
    fontFamily: 'inherit',
    boxShadow: checked ? '0 8px 18px -12px rgba(37,99,235,0.55)' : '0 1px 0 rgba(255,255,255,0.8) inset',
    transition: 'background 0.16s var(--ol-motion-quick), color 0.16s var(--ol-motion-quick), border-color 0.16s var(--ol-motion-quick), box-shadow 0.18s var(--ol-motion-soft)',
  };
}

function translationStatusStyle(enabled: boolean): CSSProperties {
  return {
    minHeight: 108,
    borderRadius: 14,
    padding: 14,
    background: enabled
      ? 'linear-gradient(135deg, rgba(37,99,235,0.12), rgba(37,99,235,0.04))'
      : 'linear-gradient(135deg, rgba(0,0,0,0.045), rgba(255,255,255,0.55))',
    border: enabled ? '0.5px solid rgba(37,99,235,0.16)' : '0.5px solid var(--ol-line)',
    boxShadow: '0 1px 0 rgba(255,255,255,0.85) inset',
  };
}

function InfoTile({ tone, title, body }: { tone: 'blue' | 'neutral'; title: string; body: string }) {
  const blue = tone === 'blue';
  return (
    <Card
      padding={14}
      style={{
        background: blue ? 'rgba(37,99,235,0.055)' : 'rgba(0,0,0,0.025)',
        border: blue ? '0.5px solid rgba(37,99,235,0.14)' : '0.5px solid var(--ol-line)',
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
        <span
          style={{
            width: 7,
            height: 7,
            borderRadius: 999,
            background: blue ? 'var(--ol-blue)' : 'var(--ol-ink-4)',
            boxShadow: blue ? '0 0 0 4px rgba(37,99,235,0.10)' : '0 0 0 4px rgba(0,0,0,0.045)',
          }}
        />
        <div style={{ fontSize: 12.5, fontWeight: 650, color: blue ? 'var(--ol-blue)' : 'var(--ol-ink-2)' }}>{title}</div>
      </div>
      <div style={{ fontSize: 11.5, color: 'var(--ol-ink-3)', lineHeight: 1.58 }}>{body}</div>
    </Card>
  );
}
