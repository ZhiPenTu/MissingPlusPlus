//! New missing form: header (gradient) + scrollable body + fixed footer (submit).
//! Mirrors the Swift `NewMissingForm` card structure: 360x720, pink-gradient header,
//! ScrollView for the fields, action button pinned to the bottom.

import { useMemo } from 'react'
import { useUI } from '../stores/ui'
import { useAddMissing, useRecords } from '../ipc/queries'
import { MOOD_EMOJI, MOOD_LABEL, INTENSITY_LABEL, TRIGGER_EMOJI, TRIGGER_LABEL } from '../domain/model'
import type { Mood, Intensity, TriggerTag, Missing } from '../domain/model'

const MOODS: Mood[] = ['happy', 'joyful', 'delighted', 'sad', 'longing']
const LEVELS: Intensity[] = ['none', 'mild', 'strong']
const TRIGGERS: TriggerTag[] = [
  'noReply', 'silent', 'fight', 'alone',
  'sawSomething', 'pastMemory', 'separation', 'comparison',
]

export function NewMissingForm() {
  const {
    who, mood, intensity, triggers,
    setWho, setMood, setIntensity, toggleTrigger, resetForm,
    setPendingRealityCheck, setShowSoothingLink,
  } = useUI()
  const { data: items } = useRecords()
  const addMissing = useAddMissing()

  const latest = items?.[0]
  const showBanner = latest && !latest.resolvedAt &&
    (Date.now() - new Date(latest.createdAt).getTime() > 30 * 60 * 1000)

  // knownWhos: unique "who" values from records, most-recent first, capped at 8
  const knownWhos = useMemo(() => {
    if (!items) return []
    const seen = new Set<string>()
    const out: string[] = []
    for (const it of items) {
      const w = (it.who || '').trim()
      if (w && !seen.has(w)) {
        seen.add(w)
        out.push(w)
        if (out.length >= 8) break
      }
    }
    return out
  }, [items])

  function handleSubmit() {
    const trimmed = who.trim()
    addMissing.mutate(
      { who: trimmed || 'TA', mood, intensity, trigger_tags: triggers },
      {
        onSuccess: (item: Missing) => {
          if (intensity === 'strong') {
            setPendingRealityCheck(item)
          } else {
            setShowSoothingLink(true)
            setTimeout(() => setShowSoothingLink(false), 5000)
          }
          resetForm()
        },
      }
    )
  }

  return (
    <div className="h-full flex flex-col bg-white">
      {/* Header — pink gradient banner with heart avatar + count */}
      <header className="px-4 pt-4 pb-3 bg-gradient-to-b from-pink-100/60 to-white">
        <div className="flex items-center gap-3">
          <div
            className="w-10 h-10 rounded-full flex items-center justify-center shadow-sm"
            style={{ background: 'linear-gradient(135deg, #EC4899 0%, #F472B6 100%)' }}
          >
            <span className="text-white text-lg leading-none">♥</span>
          </div>
          <div className="flex-1 min-w-0">
            <div className="text-sm font-semibold text-gray-900 leading-tight">思念计数器</div>
            <div className="text-xs text-gray-500 leading-tight flex items-center gap-1">
              <span>已记录 {items?.length ?? 0} 个时刻</span>
              {latest && <><span>·</span><span>{MOOD_EMOJI[latest.mood]}</span></>}
            </div>
          </div>
        </div>
      </header>

      <div className="h-px bg-gray-200" />

      {/* Scrollable form body */}
      <div className="flex-1 overflow-y-auto px-4 py-4 space-y-4">
        {showBanner && latest && (
          <ResolveLastBanner latest={latest} onResolve={() => {/* mark_resolved via hook */}} />
        )}

        <SoothingInlineLink />

        <WhoField value={who} onChange={setWho} suggestions={knownWhos} onPick={setWho} />
        <MoodPicker value={mood} onChange={setMood} />
        <IntensityPicker value={intensity} onChange={setIntensity} />
        <TriggerPicker value={triggers} onToggle={toggleTrigger} />
      </div>

      <div className="h-px bg-gray-200" />

      {/* Footer — submit button (always enabled; empty who → "TA" fallback) */}
      <footer className="px-4 py-3 bg-white">
        <button
          onClick={handleSubmit}
          disabled={addMissing.isPending}
          className="w-full flex items-center justify-center gap-2 py-2 bg-pink-500 hover:bg-pink-600 text-white text-sm font-medium rounded-md shadow-sm disabled:opacity-60 transition-colors"
        >
          <span className="text-base leading-none">✈️</span>
          <span>
            {addMissing.isPending
              ? '记录中…'
              : who.trim()
                ? '记录这一刻'
                : '记录（未指定对象）'}
          </span>
        </button>
      </footer>
    </div>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <label className="text-xs text-gray-500">{label}</label>
      {children}
    </div>
  )
}

function WhoField({
  value, onChange, suggestions, onPick,
}: {
  value: string
  onChange: (v: string) => void
  suggestions: string[]
  onPick: (v: string) => void
}) {
  return (
    <Field label="对象">
      <input
        type="text"
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder="想念 谁?"
        className="w-full px-3 py-1.5 text-sm border border-gray-200 rounded-md focus:outline-none focus:ring-2 focus:ring-pink-200 focus:border-pink-300"
      />
      {suggestions.length > 0 && (
        <div className="flex gap-1.5 overflow-x-auto pt-1 -mx-1 px-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
          {suggestions.map(name => (
            <button
              key={name}
              type="button"
              onClick={() => onPick(name)}
              className="shrink-0 px-2.5 py-0.5 text-xs border border-gray-200 rounded-full hover:bg-pink-50 hover:border-pink-200 hover:text-pink-700 text-gray-700 transition-colors"
            >
              {name}
            </button>
          ))}
        </div>
      )}
    </Field>
  )
}

function MoodPicker({ value, onChange }: { value: Mood; onChange: (m: Mood) => void }) {
  return (
    <Field label="心情">
      <div className="flex gap-1.5">
        {MOODS.map(m => {
          const selected = value === m
          return (
            <button
              key={m}
              type="button"
              onClick={() => onChange(m)}
              title={MOOD_LABEL[m]}
              className={`flex-1 py-1 text-2xl rounded-md transition-colors ${
                selected
                  ? 'bg-pink-50 ring-1 ring-pink-400'
                  : 'bg-gray-50 hover:bg-gray-100 ring-1 ring-transparent'
              }`}
            >
              {MOOD_EMOJI[m]}
            </button>
          )
        })}
      </div>
    </Field>
  )
}

function IntensityPicker({ value, onChange }: { value: Intensity; onChange: (i: Intensity) => void }) {
  return (
    <Field label="程度">
      <div className="flex border border-gray-200 rounded-md overflow-hidden">
        {LEVELS.map(l => {
          const selected = value === l
          return (
            <button
              key={l}
              type="button"
              onClick={() => onChange(l)}
              className={`flex-1 py-1.5 text-sm transition-colors ${
                selected
                  ? 'bg-pink-100 text-pink-700 font-medium'
                  : 'bg-white text-gray-600 hover:bg-gray-50'
              }`}
            >
              {INTENSITY_LABEL[l]}
            </button>
          )
        })}
      </div>
    </Field>
  )
}

function TriggerPicker({
  value, onToggle,
}: {
  value: TriggerTag[]
  onToggle: (t: TriggerTag) => void
}) {
  return (
    <Field label="触发（多选，可不选）">
      <div className="grid grid-cols-4 gap-1.5">
        {TRIGGERS.map(t => {
          const selected = value.includes(t)
          return (
            <button
              key={t}
              type="button"
              onClick={() => onToggle(t)}
              className={`px-1 py-1 text-[10px] leading-tight rounded-md whitespace-nowrap transition-colors ${
                selected
                  ? 'bg-pink-50 ring-1 ring-pink-300 text-pink-900'
                  : 'bg-gray-50 text-gray-700 hover:bg-gray-100 ring-1 ring-transparent'
              }`}
            >
              {TRIGGER_EMOJI[t]} {TRIGGER_LABEL[t]}
            </button>
          )
        })}
      </div>
    </Field>
  )
}

function ResolveLastBanner({ latest, onResolve }: {
  latest: Missing; onResolve: () => void
}) {
  return (
    <div className="flex items-start gap-2.5 p-2.5 bg-pink-50/60 rounded-md">
      <div className="flex-1 min-w-0">
        <div className="text-sm font-medium">上次想念平复了吗？</div>
        <div className="text-xs text-gray-500 truncate">对象：{latest.who}</div>
      </div>
      <div className="flex flex-col gap-1">
        <button onClick={onResolve} className="px-2.5 py-0.5 text-xs bg-pink-500 text-white rounded">是</button>
        <button className="px-2.5 py-0.5 text-xs border rounded">否</button>
        <button className="px-2.5 py-0.5 text-xs">跳过</button>
      </div>
    </div>
  )
}

function SoothingInlineLink() {
  const { showSoothingLink, setPendingGrounding, setPendingCompassion, setPendingCooldown } = useUI()
  if (!showSoothingLink) return null
  return (
    <div className="flex items-center gap-2 p-2 bg-pink-50/60 rounded-md text-xs">
      <span>✨</span>
      <span className="text-gray-600">想冷静一下？</span>
      <div className="flex-1" />
      <button onClick={() => setPendingGrounding(true)} title="5-4-3-2-1 grounding" className="text-base">👁</button>
      <button onClick={() => setPendingCompassion(true)} title="自我同情" className="text-base">💗</button>
      <button onClick={() => setPendingCooldown(true)} title="分散" className="text-base">🔀</button>
    </div>
  )
}
