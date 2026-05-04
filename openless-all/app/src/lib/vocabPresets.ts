import defaultPresetsJson from './vocab-presets.json';
import { listVocabPresets, saveVocabPresets } from './ipc';
import type { VocabPreset } from './types';

export const DEFAULT_VOCAB_PRESETS: VocabPreset[] = defaultPresetsJson as VocabPreset[];

export async function loadVocabPresets(): Promise<VocabPreset[]> {
  const userPresets = await listVocabPresets();
  if (!Array.isArray(userPresets)) {
    return DEFAULT_VOCAB_PRESETS;
  }
  const merged = new Map(DEFAULT_VOCAB_PRESETS.map(p => [p.id, p] as const));
  for (const preset of userPresets) {
    if (!preset || !preset.id) continue;
    merged.set(preset.id, preset);
  }
  return Array.from(merged.values());
}

export async function persistVocabPresets(presets: VocabPreset[]) {
  await saveVocabPresets(presets);
}
