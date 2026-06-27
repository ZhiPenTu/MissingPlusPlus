//! CooldownSheet — 1 activity + re-roll (6 defaults + user added)

import { useState, useEffect, useMemo } from 'react'
import { useUI } from '../stores/ui'
import { COOLDOWN_DEFAULTS } from '../domain/cooldown'

export function CooldownSheet() {
  const { setPendingCooldown } = useUI()
  const [custom, setCustom] = useState<string[]>([])
  const [index, setIndex] = useState(0)

  useEffect(() => {
    try { setCustom(JSON.parse(localStorage.getItem('cooldownActivities') || '[]')) }
    catch { setCustom([]) }
  }, [])

  const all = useMemo(() => COOLDOWN_DEFAULTS.concat(custom.filter(c => !COOLDOWN_DEFAULTS.includes(c))), [custom])

  useEffect(() => {
    if (all.length > 0) setIndex(Math.floor(Math.random() * all.length))
  }, [all.length])

  function reroll() {
    if (all.length === 0) return
    let next = index
    while (next === index && all.length > 1) next = Math.floor(Math.random() * all.length)
    setIndex(next)
  }

  return (
    <Modal title="分散注意力" onClose={() => setPendingCooldown(false)}>
      <p className="text-xs text-gray-500 -mt-1">从清单里挑一件做 5 分钟，让情绪过一下。</p>

      {all.length === 0 ? (
        <p className="text-center text-sm text-gray-500 py-6">没有 cooldown 活动了 —— 去 settings 加几条。</p>
      ) : (
        <p className="text-xl font-medium text-center py-8 px-3 bg-purple-50/50 rounded">
          {all[index]}
        </p>
      )}

      <div className="flex justify-between">
        <button onClick={reroll} disabled={all.length === 0} className="px-3 py-1 text-xs border rounded disabled:opacity-50">再抽一个</button>
        <button onClick={() => setPendingCooldown(false)} className="px-3 py-1 text-xs bg-pink-500 text-white rounded">关闭</button>
      </div>
    </Modal>
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
