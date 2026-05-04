import defaultPresetsJson from './vocab-presets.json';
import { listVocabPresets, saveVocabPresets } from './ipc';
import type { VocabPreset } from './types';

export const DEFAULT_VOCAB_PRESETS: VocabPreset[] = defaultPresetsJson as VocabPreset[];

export async function loadVocabPresets(): Promise<VocabPreset[]> {
  const userPresets = await listVocabPresets();
  if (!Array.isArray(userPresets) || userPresets.length === 0) {
    return DEFAULT_VOCAB_PRESETS;
  }
  return userPresets;
}

export async function persistVocabPresets(presets: VocabPreset[]) {
  await saveVocabPresets(presets);
}
