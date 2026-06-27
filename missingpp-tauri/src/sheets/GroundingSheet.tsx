//! GroundingSheet — 5-4-3-2-1 sensory grounding, step-by-step

import { useState } from 'react'
import { useUI } from '../stores/ui'

const SENSES: { sense: string; prompt: string }[] = [
  { sense: '看', prompt: '慢慢环顾四周，说出你能看到的 5 样东西。' },
  { sense: '听', prompt: '现在注意听，说出你能听到的 4 种声音。' },
  { sense: '触', prompt: '感受身体接触的 3 样东西（椅子/衣服/手）。' },
  { sense: '闻', prompt: '找出空气中的 2 种气味。' },
  { sense: '尝', prompt: '注意你嘴里的 1 种味道。' },
]

export function GroundingSheet() {
  const { setPendingGrounding } = useUI()
  const [step, setStep] = useState(0)

  function close() { setStep(0); setPendingGrounding(false) }
  function next() { setStep(s => s + 1) }
  function restart() { setStep(0) }

  const done = step >= SENSES.length

  return (
    <Modal title="5-4-3-2-1 grounding" onClose={close}>
      {done ? (
        <div className="text-center space-y-3 py-6">
          <div className="text-4xl">🌿</div>
          <div className="font-medium">你刚刚做了一次 grounding</div>
          <div className="text-xs text-gray-500">想关掉就点下面；想再来一次也行。</div>
          <div className="flex justify-center gap-2">
            <button onClick={restart} className="px-3 py-1 text-xs border rounded">再来一次</button>
            <button onClick={close} className="px-3 py-1 text-xs bg-pink-500 text-white rounded">关闭</button>
          </div>
        </div>
      ) : (
        <>
          <div className="flex items-center justify-between text-xs text-gray-500">
            <span>{step + 1} / {SENSES.length}</span>
            <span>{SENSES[step].sense}</span>
          </div>
          <p className="text-lg leading-relaxed py-6">{SENSES[step].prompt}</p>
          <div className="flex justify-end">
            <button
              onClick={next}
              className="px-4 py-1.5 text-sm bg-pink-500 text-white rounded"
            >
              {step < SENSES.length - 1 ? '下一个' : '完成'}
            </button>
          </div>
        </>
      )}
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
