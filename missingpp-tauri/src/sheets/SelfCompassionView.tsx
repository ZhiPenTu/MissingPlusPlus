//! SelfCompassionView — 1 phrase + re-roll (17 curated)

import { useState } from 'react'
import { useUI } from '../stores/ui'
import { SELF_COMPASSION_PHRASES } from '../domain/phrases'

export function SelfCompassionView() {
  const { setPendingCompassion } = useUI()
  const [index, setIndex] = useState(() => randomIndex())

  function reroll() {
    let next = index
    while (next === index && SELF_COMPASSION_PHRASES.length > 1) {
      next = randomIndex()
    }
    setIndex(next)
  }

  return (
    <Modal title="自我同情" onClose={() => setPendingCompassion(false)}>
      <p className="text-xs text-gray-500 -mt-1">DBT / Kristin Neff：对自己说一句有用的话。</p>
      <p className="text-lg leading-relaxed px-3 py-8 bg-pink-50/50 rounded">
        {SELF_COMPASSION_PHRASES[index]}
      </p>
      <div className="flex justify-between">
        <button onClick={reroll} className="px-3 py-1 text-xs border rounded">再抽一句</button>
        <button onClick={() => setPendingCompassion(false)} className="px-3 py-1 text-xs bg-pink-500 text-white rounded">关闭</button>
      </div>
    </Modal>
  )
}

function randomIndex() {
  return Math.floor(Math.random() * SELF_COMPASSION_PHRASES.length)
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
