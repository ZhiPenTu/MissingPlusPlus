//! UI state (form draft / sheet pending / tab) — transient, no Rust round-trip

import { create } from 'zustand'
import type { Missing, Mood, Intensity, TriggerTag } from '../domain/model'

export type View = 'menu' | 'popover'
export type Tab = 'new' | 'stats' | 'history'

interface UIState {
  // which window
  view: View
  setView: (v: View) => void

  // current tab in main window
  tab: Tab
  setTab: (t: Tab) => void

  // form draft
  who: string
  mood: Mood
  intensity: Intensity
  triggers: TriggerTag[]
  setWho: (v: string) => void
  setMood: (m: Mood) => void
  setIntensity: (i: Intensity) => void
  toggleTrigger: (t: TriggerTag) => void
  resetForm: () => void

  // pending sheets (per-card)
  pendingRealityCheck: Missing | null
  pendingGrounding: boolean
  pendingCompassion: boolean
  pendingCooldown: boolean
  setPendingRealityCheck: (m: Missing | null) => void
  setPendingGrounding: (v: boolean) => void
  setPendingCompassion: (v: boolean) => void
  setPendingCooldown: (v: boolean) => void

  // mild submit inline link
  showSoothingLink: boolean
  setShowSoothingLink: (v: boolean) => void
}

export const useUI = create<UIState>((set) => ({
  view: 'menu',
  setView: (v) => set({ view: v }),

  tab: 'new',
  setTab: (t) => set({ tab: t }),

  who: '',
  mood: 'happy',
  intensity: 'mild',
  triggers: [],
  setWho: (v) => set({ who: v }),
  setMood: (m) => set({ mood: m }),
  setIntensity: (i) => set({ intensity: i }),
  toggleTrigger: (t) => set(s => ({
    triggers: s.triggers.includes(t)
      ? s.triggers.filter(x => x !== t)
      : [...s.triggers, t],
  })),
  resetForm: () => set({
    who: '', mood: 'happy', intensity: 'mild', triggers: [],
  }),

  pendingRealityCheck: null,
  pendingGrounding: false,
  pendingCompassion: false,
  pendingCooldown: false,
  setPendingRealityCheck: (m) => set({ pendingRealityCheck: m }),
  setPendingGrounding: (v) => set({ pendingGrounding: v }),
  setPendingCompassion: (v) => set({ pendingCompassion: v }),
  setPendingCooldown: (v) => set({ pendingCooldown: v }),

  showSoothingLink: false,
  setShowSoothingLink: (v) => set({ showSoothingLink: v }),
}))
