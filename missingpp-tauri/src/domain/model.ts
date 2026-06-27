//! Mirror Rust data model in src-tauri/src/data/model.rs

export type Mood = 'happy' | 'joyful' | 'delighted' | 'sad' | 'longing'
export type Intensity = 'none' | 'mild' | 'strong'
export type TriggerTag =
  | 'noReply' | 'silent' | 'fight' | 'alone'
  | 'sawSomething' | 'pastMemory' | 'separation' | 'comparison'

export interface RealityCheck {
  evidenceFor?: string
  evidenceAgainst?: string
  nextAction?: string
  checkedAt: string
}

export interface Missing {
  id: string
  who: string
  mood: Mood
  intensity: Intensity
  createdAt: string
  triggerTags: TriggerTag[]
  resolvedAt?: string
  realityCheck?: RealityCheck
}

export const MOOD_EMOJI: Record<Mood, string> = {
  happy: '😊', joyful: '😄', delighted: '🥰', sad: '😢', longing: '🥺',
}

export const MOOD_LABEL: Record<Mood, string> = {
  happy: '开心', joyful: '愉悦', delighted: '欢乐', sad: '难过', longing: '思念',
}

export const INTENSITY_LABEL: Record<Intensity, string> = {
  none: '无', mild: '一般', strong: '非常',
}

export const TRIGGER_EMOJI: Record<TriggerTag, string> = {
  noReply: '💬', silent: '🔇', fight: '⚡️', alone: '🏠',
  sawSomething: '👀', pastMemory: '🕰', separation: '✈️', comparison: '🪞',
}

export const TRIGGER_LABEL: Record<TriggerTag, string> = {
  noReply: 'TA 没及时回', silent: 'TA 没说想我', fight: '刚吵完架', alone: '独处时',
  sawSomething: '看到某物/某地', pastMemory: '想到过去',
  separation: '分离/即将分离', comparison: '比较/嫉妒',
}

export const TRIGGER_DISPLAY: Record<TriggerTag, string> = (() => {
  const out = {} as Record<TriggerTag, string>
  ;(Object.keys(TRIGGER_EMOJI) as TriggerTag[]).forEach(t => {
    out[t] = `${TRIGGER_EMOJI[t]} ${TRIGGER_LABEL[t]}`
  })
  return out
})()
