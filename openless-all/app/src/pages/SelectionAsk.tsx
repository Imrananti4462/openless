// SelectionAsk.tsx — 独立的"划词追问"页（issue #118 / PR #119 配置 UI 拆分版）。
// 功能：用户在任意 app 选中一段文字 → 按 hotkey → 浮窗弹出 + 进入语音录音 →
// 用户口述提问 → ASR + 选区 + 提问 一起送 LLM → 答案以 markdown 显示在浮窗。
//
// 这一页把原本散在 Settings → 录音 里的两条配置（hotkey 预设 / 保存 Q&A 历史）
// 集中起来 + 加完整使用指南，跟"翻译"页平级。

import { useTranslation } from 'react-i18next';
import { Card, PageHeader } from './_atoms';
import { useHotkeySettings } from '../state/HotkeySettingsContext';
import { setQaHotkey } from '../lib/ipc';
import type { QaHotkeyBinding } from '../lib/types';

const QA_HOTKEY_DISABLED_ID = 'disabled' as const;

interface QaHotkeyPreset {
  id: string;
  binding: QaHotkeyBinding;
  label: string;
}

const QA_HOTKEY_PRESETS: readonly QaHotkeyPreset[] = [
  // 双修饰键 chord（Cmd+Option / Ctrl+Alt）默认排第一——用户偏好的纯组合键。
  // 后端实现需要 CGEventTap 的"双修饰键按下后无其他键插入即释放"模式（待后端补）。
  { id: 'cmd+option',   label: 'Cmd+Option',   binding: { primary: '', modifiers: ['cmd', 'option'] } },
  { id: 'cmd+shift+;',  label: 'Cmd+Shift+;',  binding: { primary: ';', modifiers: ['cmd', 'shift']  } },
  { id: 'cmd+option+;', label: 'Cmd+Option+;', binding: { primary: ';', modifiers: ['cmd', 'option'] } },
  { id: 'cmd+shift+/',  label: 'Cmd+Shift+/',  binding: { primary: '/', modifiers: ['cmd', 'shift']  } },
  { id: 'cmd+option+/', label: 'Cmd+Option+/', binding: { primary: '/', modifiers: ['cmd', 'option'] } },
] as const;

function bindingToPresetId(binding: QaHotkeyBinding | null): string {
  if (!binding) return QA_HOTKEY_DISABLED_ID;
  const sortedMods = [...binding.modifiers].map(m => m.toLowerCase()).sort();
  const match = QA_HOTKEY_PRESETS.find(p => {
    const pMods = [...p.binding.modifiers].sort();
    return p.binding.primary === binding.primary
      && pMods.length === sortedMods.length
      && pMods.every((m, i) => m === sortedMods[i]);
  });
  return match ? match.id : QA_HOTKEY_PRESETS[0].id;
}

export function SelectionAsk() {
  const { t } = useTranslation();
  const { prefs, updatePrefs: savePrefs } = useHotkeySettings();

  if (!prefs) {
    return (
      <>
        <PageHeader
          kicker={t('selectionAsk.kicker')}
          title={t('selectionAsk.title')}
          desc={t('selectionAsk.desc')}
        />
        <Card>
          <div style={{ fontSize: 12, color: 'var(--ol-ink-4)' }}>{t('common.loading')}</div>
        </Card>
      </>
    );
  }

  const onHotkeyChange = async (id: string) => {
    if (id === QA_HOTKEY_DISABLED_ID) {
      await savePrefs({ ...prefs, qaHotkey: null });
      return;
    }
    const preset = QA_HOTKEY_PRESETS.find(p => p.id === id);
    if (!preset) return;
    try {
      await setQaHotkey(preset.binding);
    } catch (error) {
      console.error('[selectionAsk] failed to set qa hotkey', error);
    }
    await savePrefs({ ...prefs, qaHotkey: preset.binding });
  };

  const onSaveHistoryChange = (qaSaveHistory: boolean) =>
    savePrefs({ ...prefs, qaSaveHistory });

  const enabled = prefs.qaHotkey !== null;
  const currentId = bindingToPresetId(prefs.qaHotkey);
  const currentLabel = QA_HOTKEY_PRESETS.find(p => p.id === currentId)?.label ?? '';

  return (
    <>
      <PageHeader
        kicker={t('selectionAsk.kicker')}
        title={t('selectionAsk.title')}
        desc={t('selectionAsk.desc')}
      />

      <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>

        {/* 1. 触发快捷键 */}
        <Card>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
            <div style={{ fontSize: 13, fontWeight: 600 }}>{t('selectionAsk.hotkey.title')}</div>
            <span
              style={{
                padding: '2px 8px',
                fontSize: 10.5,
                fontWeight: 600,
                letterSpacing: '0.04em',
                borderRadius: 999,
                background: enabled ? 'rgba(37,99,235,0.10)' : 'rgba(0,0,0,0.05)',
                color: enabled ? 'var(--ol-blue)' : 'var(--ol-ink-4)',
                textTransform: 'uppercase',
              }}
            >
              {enabled ? t('selectionAsk.statusEnabled') : t('selectionAsk.statusDisabled')}
            </span>
          </div>
          <div style={{ fontSize: 11.5, color: 'var(--ol-ink-4)', marginBottom: 12, lineHeight: 1.55 }}>
            {t('selectionAsk.hotkey.desc')}
          </div>
          <select
            value={currentId}
            onChange={e => onHotkeyChange(e.target.value)}
            style={{
              width: '100%',
              maxWidth: 360,
              height: 32,
              padding: '0 10px',
              fontSize: 13,
              border: '0.5px solid var(--ol-line-strong)',
              borderRadius: 8,
              background: '#fff',
              color: 'var(--ol-ink)',
              fontFamily: 'inherit',
              cursor: 'default',
            }}
          >
            <option value={QA_HOTKEY_DISABLED_ID}>{t('selectionAsk.hotkey.optionDisabled')}</option>
            {QA_HOTKEY_PRESETS.map(p => (
              <option key={p.id} value={p.id}>{p.label}</option>
            ))}
          </select>
          {currentId === 'cmd+option' && (
            <div
              style={{
                marginTop: 10,
                padding: '8px 10px',
                borderRadius: 8,
                background: 'rgba(217, 119, 6, 0.08)',
                border: '0.5px solid rgba(217, 119, 6, 0.2)',
                fontSize: 11.5,
                color: 'var(--ol-warn)',
                lineHeight: 1.55,
              }}
            >
              {t('selectionAsk.hotkey.chordWarning')}
            </div>
          )}
        </Card>

        {/* 2. 历史保存 */}
        <Card>
          <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 4 }}>{t('selectionAsk.history.title')}</div>
          <div style={{ fontSize: 11.5, color: 'var(--ol-ink-4)', marginBottom: 12, lineHeight: 1.55 }}>
            {t('selectionAsk.history.desc')}
          </div>
          <button
            onClick={() => onSaveHistoryChange(!prefs.qaSaveHistory)}
            style={{
              position: 'relative',
              width: 44,
              height: 24,
              borderRadius: 999,
              border: 0,
              background: prefs.qaSaveHistory ? 'var(--ol-blue)' : 'rgba(0,0,0,0.18)',
              cursor: 'default',
              transition: 'background 0.15s ease-out',
              padding: 0,
            }}
          >
            <span
              style={{
                position: 'absolute',
                top: 2,
                left: prefs.qaSaveHistory ? 22 : 2,
                width: 20,
                height: 20,
                borderRadius: 999,
                background: '#fff',
                boxShadow: '0 1px 2px rgba(0,0,0,.18)',
                transition: 'left .15s',
              }}
            />
          </button>
        </Card>

        {/* 3. 使用方法 */}
        <Card>
          <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 10 }}>{t('selectionAsk.howto.title')}</div>
          <ol style={{ margin: 0, paddingLeft: 18, fontSize: 12.5, color: 'var(--ol-ink-2)', lineHeight: 1.7 }}>
            <li>{t('selectionAsk.howto.step1')}</li>
            <li>{t('selectionAsk.howto.step2', { hotkey: enabled ? currentLabel : '快捷键' })}</li>
            <li>{t('selectionAsk.howto.step3')}</li>
            <li>{t('selectionAsk.howto.step4', { hotkey: enabled ? currentLabel : '快捷键' })}</li>
            <li>{t('selectionAsk.howto.step5')}</li>
          </ol>

          <div
            style={{
              marginTop: 14,
              padding: '10px 12px',
              borderRadius: 10,
              background: 'rgba(37,99,235,0.06)',
              border: '0.5px solid rgba(37,99,235,0.15)',
              fontSize: 11.5,
              color: 'var(--ol-ink-2)',
              lineHeight: 1.55,
            }}
          >
            <div style={{ fontWeight: 600, color: 'var(--ol-blue)', marginBottom: 4 }}>{t('selectionAsk.howto.windowTitle')}</div>
            {t('selectionAsk.howto.windowDesc')}
          </div>

          <div
            style={{
              marginTop: 10,
              padding: '10px 12px',
              borderRadius: 10,
              background: 'rgba(0,0,0,0.04)',
              fontSize: 11.5,
              color: 'var(--ol-ink-3)',
              lineHeight: 1.55,
            }}
          >
            <div style={{ fontWeight: 600, color: 'var(--ol-ink-2)', marginBottom: 4 }}>{t('selectionAsk.howto.privacyTitle')}</div>
            {t('selectionAsk.howto.privacyDesc')}
          </div>
        </Card>
      </div>
    </>
  );
}
