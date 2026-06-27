//! New missing form: 5 fields (who / mood / intensity / trigger picker) + submit


import { useUI } from '../stores/ui'
import { useAddMissing, useRecords } from '../ipc/queries'
import { MOOD_EMOJI, MOOD_LABEL, INTENSITY_LABEL, TRIGGER_DISPLAY } from '../domain/model'
import type { Mood, Intensity, TriggerTag, Missing } from '../domain/model'

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

  function handleSubmit() {
    addMissing.mutate(
      { who: who.trim() || 'TA', mood, intensity, trigger_tags: triggers },
      {
        onSuccess: (item) => {
          if (intensity === 'strong') {
            // auto-pop reality check sheet
            setPendingRealityCheck(item)
          } else {
            // mild: show 5s "想冷静一下?" link
            setShowSoothingLink(true)
            setTimeout(() => setShowSoothingLink(false), 5000)
          }
          resetForm()
        },
      }
    )
  }

  return (
    <div className="p-4 space-y-4">
      {/* "上一条平复了吗" banner */}
      {showBanner && latest && (
        <ResolveLastBanner
          latest={latest}
          onResolve={() => {
            // call mark_resolved via direct query client
            // (in real impl, use hook)
          }}
        />
      )}

      {/* mild 5s inline "想冷静一下?" link */}
      <SoothingInlineLink />

      {/* Header */}
      <Header itemCount={items?.length ?? 0} latestMood={latest?.mood} />

      {/* Form fields */}
      <WhoField value={who} onChange={setWho} />
      <MoodPicker value={mood} onChange={setMood} />
      <IntensityPicker value={intensity} onChange={setIntensity} />
      <TriggerPicker value={triggers} onToggle={toggleTrigger} />

      {/* Submit */}
      <button
        onClick={handleSubmit}
        disabled={addMissing.isPending}
        className="w-full py-2.5 bg-pink-500 text-white font-medium rounded-md hover:bg-pink-600 disabled:opacity-50"
      >
        {addMissing.isPending ? '记录中…' :
         who.trim() ? '记录这一刻' : '记录（未指定对象）'}
      </button>
    </div>
  )
}

function Header({ itemCount, latestMood }: { itemCount: number; latestMood?: Mood }) {
  return (
    <div className="flex items-center gap-3 pb-3 border-b bg-gradient-to-b from-pink-50/30 to-transparent">
      <div className="w-10 h-10 rounded-full bg-gradient-to-br from-pink-500 to-pink-400 flex items-center justify-center shadow-sm">
        <span className="text-white text-lg">♥</span>
      </div>
      <div className="text-left">
        <div className="text-sm font-medium">思念计数器</div>
        <div className="text-xs text-gray-500">
          已记录 {itemCount} 个时刻
          {latestMood && <span className="ml-1.5">{MOOD_EMOJI[latestMood]}</span>}
        </div>
      </div>
    </div>
  )
}

function WhoField({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return (
    <Field label="对象">
      <input
        type="text"
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder="想念 谁？"
        className="w-full px-3 py-2 text-sm border border-gray-200 rounded-md focus:outline-none focus:ring-2 focus:ring-pink-200"
      />
    </Field>
  )
}

function MoodPicker({ value, onChange }: { value: Mood; onChange: (m: Mood) => void }) {
  const moods: Mood[] = ['happy', 'joyful', 'delighted', 'sad', 'longing']
  return (
    <Field label="心情">
      <div className="flex gap-1.5">
        {moods.map(m => (
          <button
            key={m}
            onClick={() => onChange(m)}
            title={MOOD_LABEL[m]}
            className={`flex-1 py-1.5 text-xl rounded-md transition-colors ${
              value === m
                ? 'bg-pink-50 ring-1 ring-pink-300'
                : 'bg-gray-50 hover:bg-gray-100'
            }`}
          >
            {MOOD_EMOJI[m]}
          </button>
        ))}
      </div>
    </Field>
  )
}

function IntensityPicker({ value, onChange }: { value: Intensity; onChange: (i: Intensity) => void }) {
  const levels: Intensity[] = ['none', 'mild', 'strong']
  return (
    <Field label="程度">
      <div className="flex gap-0 border border-gray-200 rounded-md overflow-hidden">
        {levels.map(l => (
          <button
            key={l}
            onClick={() => onChange(l)}
            className={`flex-1 py-1.5 text-sm ${
              value === l
                ? 'bg-pink-100 text-pink-700 font-medium'
                : 'bg-white text-gray-600 hover:bg-gray-50'
            }`}
          >
            {INTENSITY_LABEL[l]}
          </button>
        ))}
      </div>
    </Field>
  )
}

function TriggerPicker({ value, onToggle }: { value: TriggerTag[]; onToggle: (t: TriggerTag) => void }) {
  const all: TriggerTag[] = ['noReply', 'silent', 'fight', 'alone', 'sawSomething', 'pastMemory', 'separation', 'comparison']
  return (
    <Field label="触发（多选，可不选）">
      <div className="grid grid-cols-4 gap-1.5">
        {all.map(t => {
          const selected = value.includes(t)
          return (
            <button
              key={t}
              onClick={() => onToggle(t)}
              className={`px-2 py-1 text-xs rounded transition-colors truncate ${
                selected
                  ? 'bg-pink-50 ring-1 ring-pink-300 text-pink-900'
                  : 'bg-gray-50 text-gray-700 hover:bg-gray-100'
              }`}
            >
              {TRIGGER_DISPLAY[t]}
            </button>
          )
        })}
      </div>
    </Field>
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

function ResolveLastBanner({ latest, onResolve }: {
  latest: Missing; onResolve: () => void
}) {
  return (
    <div className="flex items-start gap-2.5 p-2.5 bg-pink-50/60 rounded-md">
      <div className="flex-1">
        <div className="text-sm font-medium">上次想念平复了吗？</div>
        <div className="text-xs text-gray-500">对象：{latest.who}</div>
      </div>
      <div className="flex flex-col gap-1">
        <button onClick={onResolve} className="px-3 py-0.5 text-xs bg-pink-500 text-white rounded">是</button>
        <button className="px-3 py-0.5 text-xs border rounded">否</button>
        <button className="px-3 py-0.5 text-xs">跳过</button>
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
      <button onClick={() => setPendingGrounding(true)} title="5-4-3-2-1 grounding">👁</button>
      <button onClick={() => setPendingCompassion(true)} title="自我同情">💗</button>
      <button onClick={() => setPendingCooldown(true)} title="分散">🔀</button>
    </div>
  )
}
