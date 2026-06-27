//! Settings — 5 sections (storage / statusbar / 依恋辅助 / cooldown / data)

import { useState } from 'react'
import { COOLDOWN_DEFAULTS } from '../domain/cooldown'

export function SettingsView() {
  return (
    <div className="p-3 space-y-3 text-sm">
      <Section title="存储位置">
        <StoragePathRow />
      </Section>
      <Section title="状态栏">
        <StatusbarSection />
      </Section>
      <Section title="依恋辅助">
        <AttachmentBundleSection />
      </Section>
      <Section title="Cooldown 活动">
        <CooldownSection />
      </Section>
      <Section title="数据">
        <DataSection />
      </Section>
    </div>
  )
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="border border-gray-200 rounded-md p-2.5">
      <div className="text-xs font-medium text-gray-500 mb-2">{title}</div>
      {children}
    </div>
  )
}

function StoragePathRow() {
  return (
    <div className="text-xs">
      <div className="text-gray-500">~/Library/Application Support/MissingPlusPlus/</div>
      <div className="mt-1 flex gap-1.5">
        <button className="px-2 py-1 border rounded text-xs">更改…</button>
        <button className="px-2 py-1 border rounded text-xs">恢复默认</button>
      </div>
    </div>
  )
}

function StatusbarSection() {
  return (
    <div className="space-y-1.5">
      <Toggle label="在状态栏显示图标" defaultChecked />
      <Toggle label="Dock 显示图标" defaultChecked />
    </div>
  )
}

function AttachmentBundleSection() {
  return (
    <div className="space-y-1.5">
      <Toggle label="高强度时弹出现实检验" defaultChecked />
      <Toggle label="新建时回访「上一条平复了吗」" defaultChecked />
      <Toggle label="通知里带 trigger 信息" defaultChecked />
      <p className="text-[10px] text-gray-400 pt-1">
        这些工具帮助焦虑型依恋人格看见 trigger 模式、累积「浪会过去」的证据。
      </p>
    </div>
  )
}

function CooldownSection() {
  const [custom, setCustom] = useState<string[]>(() => {
    try { return JSON.parse(localStorage.getItem('cooldownActivities') || '[]') } catch { return [] }
  })
  const [text, setText] = useState('')

  function persist(next: string[]) {
    setCustom(next)
    localStorage.setItem('cooldownActivities', JSON.stringify(next))
  }

  function add() {
    const t = text.trim()
    if (!t) return
    if (COOLDOWN_DEFAULTS.includes(t) || custom.includes(t)) return
    persist([...custom, t])
    setText('')
  }

  function remove(item: string) {
    persist(custom.filter(x => x !== item))
  }

  const all = [...COOLDOWN_DEFAULTS, ...custom]

  return (
    <div>
      {all.map(item => {
        const isDefault = COOLDOWN_DEFAULTS.includes(item)
        return (
          <div key={item} className="flex items-center gap-2 py-1 text-xs">
            <span className="flex-1">{item}</span>
            {isDefault ? (
              <span className="text-gray-400 text-[10px]">🔒</span>
            ) : (
              <button onClick={() => remove(item)} className="text-gray-400 hover:text-red-500">
                ✕
              </button>
            )}
          </div>
        )
      })}
      <div className="flex gap-1.5 mt-2">
        <input
          value={text}
          onChange={e => setText(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && add()}
          placeholder="加一条你自己的…"
          className="flex-1 px-2 py-1 text-xs border rounded"
        />
        <button
          onClick={add}
          disabled={!text.trim()}
          className="px-2 py-1 text-xs border rounded disabled:opacity-50"
        >
          添加
        </button>
      </div>
      <p className="text-[10px] text-gray-400 mt-1.5">🔒 标记的是预定义 6 条（不能删）。你追加的可以删。</p>
    </div>
  )
}

function DataSection() {
  return (
    <div className="space-y-1.5">
      <div className="flex gap-1.5">
        <button className="px-2 py-1 border rounded text-xs">↑ 导出数据…</button>
        <button className="px-2 py-1 border rounded text-xs">↓ 导入数据…</button>
        <button className="px-2 py-1 border rounded text-xs text-red-600">🗑 清空所有记录</button>
      </div>
      <p className="text-[10px] text-gray-400">导入时会按记录 ID 去重</p>
    </div>
  )
}

function Toggle({ label, defaultChecked }: { label: string; defaultChecked?: boolean }) {
  const [on, setOn] = useState(defaultChecked ?? false)
  return (
    <label className="flex items-center gap-2 cursor-pointer">
      <input type="checkbox" checked={on} onChange={e => setOn(e.target.checked)} className="rounded" />
      <span className="text-xs">{label}</span>
    </label>
  )
}
