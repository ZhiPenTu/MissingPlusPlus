//! RealityCheckSheet — DBT "Check the Facts" (3 TextField + 保存/跳过 + 3 sub-button)

import { useState } from 'react'
import { useUI } from '../stores/ui'
import { useAttachRealityCheck } from '../ipc/queries'

export function RealityCheckSheet() {
  const { pendingRealityCheck, setPendingRealityCheck, setPendingGrounding, setPendingCompassion, setPendingCooldown } = useUI()
  const attachRC = useAttachRealityCheck()
  const [evidenceFor, setEvidenceFor] = useState('')
  const [evidenceAgainst, setEvidenceAgainst] = useState('')
  const [nextAction, setNextAction] = useState('')

  if (!pendingRealityCheck) return null
  const item = pendingRealityCheck

  const trim = (s: string) => s.trim() || undefined
  const canSave = !!(trim(evidenceFor) || trim(evidenceAgainst) || trim(nextAction))

  function handleSave() {
    attachRC.mutate(
      {
        id: item.id,
        check: {
          evidenceFor: trim(evidenceFor),
          evidenceAgainst: trim(evidenceAgainst),
          nextAction: trim(nextAction),
          checkedAt: new Date().toISOString(),
        },
      },
      { onSuccess: () => setPendingRealityCheck(null) }
    )
  }

  return (
    <Modal title="现实检验" onClose={() => setPendingRealityCheck(null)}>
      <p className="text-xs text-gray-500 -mt-1">
        DBT 的「Check the Facts」：写下来，情绪就变成可观察的事实。
      </p>

      <Field title="这次想念的证据是…" placeholder="比如：TA 5h 没回我消息" value={evidenceFor} onChange={setEvidenceFor} />
      <Field title="反对的证据是…" placeholder="比如：上周 TA 也这样，后来回我说在加班" value={evidenceAgainst} onChange={setEvidenceAgainst} />
      <Field title="我接下来会…" placeholder="比如：再等 30 分钟；不主动发消息" value={nextAction} onChange={setNextAction} />

      <div className="flex justify-end gap-2 pt-2">
        <button onClick={() => setPendingRealityCheck(null)} className="px-3 py-1 text-xs border rounded">跳过</button>
        <button onClick={handleSave} disabled={!canSave} className="px-3 py-1 text-xs bg-pink-500 text-white rounded disabled:opacity-50">保存</button>
      </div>

      <div className="border-t pt-2 mt-2 flex items-center gap-2 text-xs text-gray-500">
        <span>想先做点别的？</span>
        <div className="flex-1" />
        <button onClick={() => setPendingGrounding(true)} className="text-blue-500" title="5-4-3-2-1 grounding">👁</button>
        <button onClick={() => setPendingCompassion(true)} className="text-pink-500" title="自我同情">💗</button>
        <button onClick={() => setPendingCooldown(true)} className="text-purple-500" title="分散注意力">🔀</button>
      </div>
    </Modal>
  )
}

function Field({ title, placeholder, value, onChange }: {
  title: string; placeholder: string; value: string; onChange: (v: string) => void
}) {
  return (
    <div>
      <label className="text-xs text-gray-500">{title}</label>
      <textarea
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
        rows={2}
        className="w-full px-2 py-1 text-sm border border-gray-200 rounded mt-0.5 focus:outline-none focus:ring-2 focus:ring-pink-200"
      />
    </div>
  )
}

function Modal({ title, onClose, children }: {
  title: string; onClose: () => void; children: React.ReactNode
}) {
  return (
    <div className="fixed inset-0 bg-black/30 flex items-center justify-center z-50" onClick={onClose}>
      <div className="bg-white rounded-lg shadow-xl w-[420px] p-5 space-y-3" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <h2 className="font-medium">{title}</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600">✕</button>
        </div>
        {children}
      </div>
    </div>
  )
}
