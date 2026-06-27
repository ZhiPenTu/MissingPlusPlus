//! History list — compact card layout, date groups, 20 cap, load more

import { useState, useMemo } from 'react'
import { useRecords, useMarkResolved } from '../ipc/queries'
import { useUI } from '../stores/ui'
import { bucketFor, BUCKET_LABEL, relativeTime } from '../domain/bucket'
import {
  MOOD_EMOJI, INTENSITY_LABEL, TRIGGER_DISPLAY,
} from '../domain/model'
import type { Missing, Mood } from '../domain/model'

const PAGE_SIZE = 20

export function HistoryList() {
  const { data: items = [] } = useRecords()
  const [query, setQuery] = useState('')
  const [showingAll, setShowingAll] = useState(false)

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    const matched = q
      ? items.filter(i => i.who.toLowerCase().includes(q))
      : items
    return matched.slice(0, showingAll ? 100 : PAGE_SIZE)
  }, [items, query, showingAll])

  const sectioned = useMemo(() => {
    const out: Array<{ kind: 'header'; label: string } | { kind: 'row'; item: Missing }> = []
    let last: string | null = null
    for (const item of filtered) {
      const bucket = bucketFor(new Date(item.createdAt))
      if (bucket !== last) {
        out.push({ kind: 'header', label: BUCKET_LABEL[bucket] })
        last = bucket
      }
      out.push({ kind: 'row', item })
    }
    return out
  }, [filtered])

  const hasMore = items.length > filtered.length

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="flex items-center justify-between px-3 pt-2 pb-1 text-xs text-gray-500">
        <span>{query ? '搜索' : '最近'}</span>
        <span>{filtered.length} / {items.length} 条</span>
      </div>

      {/* Search */}
      <div className="px-3 pb-2">
        <div className="flex items-center gap-1.5 px-2 py-1.5 bg-gray-100 rounded">
          <span className="text-gray-400">🔍</span>
          <input
            value={query}
            onChange={e => setQuery(e.target.value)}
            placeholder="按对象搜索"
            className="flex-1 bg-transparent text-sm focus:outline-none"
          />
        </div>
      </div>

      {/* Empty state */}
      {filtered.length === 0 && (
        <div className="flex-1 flex flex-col items-center justify-center text-gray-400 text-sm">
          <div className="text-3xl mb-2">💭</div>
          <div>{query ? '没有匹配的记录' : '还没有记录'}</div>
          <div className="text-xs text-gray-400 mt-1">
            {query ? '试试别的关键字' : '想念的时候就来记一笔吧'}
          </div>
        </div>
      )}

      {/* List */}
      <div className="flex-1 overflow-auto">
        {sectioned.map((s, i) =>
          s.kind === 'header' ? (
            <div key={`h-${i}`} className="px-3 pt-3 pb-1 text-xs font-semibold text-gray-500">
              {s.label}
            </div>
          ) : (
            <HistoryRow key={s.item.id} item={s.item} />
          )
        )}

        {hasMore && !showingAll && (
          <button
            onClick={() => setShowingAll(true)}
            className="w-full py-3 text-xs text-pink-600 hover:bg-pink-50"
          >
            加载更多… ↓
          </button>
        )}
      </div>
    </div>
  )
}

function HistoryRow({ item }: { item: Missing }) {
  const {
    setPendingRealityCheck, setPendingGrounding, setPendingCompassion, setPendingCooldown,
  } = useUI()
  const markResolved = useMarkResolved()

  return (
    <div className="px-3 py-1 border-b border-gray-100 hover:bg-gray-50">
      {/* Top row: who · intensity · time + actions */}
      <div className="flex items-center gap-1 text-sm">
        <span>{MOOD_EMOJI[item.mood]}</span>
        <span className="font-medium truncate">{item.who}</span>
        <span className="text-gray-400">·</span>
        <span className="text-xs text-gray-500">{INTENSITY_LABEL[item.intensity]}</span>
        <span className="text-gray-400">·</span>
        <span className="text-xs text-gray-500">{relativeTime(new Date(item.createdAt))}</span>
        <div className="flex-1" />

        {/* Resolved toggle */}
        {item.resolvedAt ? (
          <button
            onClick={() => markResolved.mutate(item.id)}
            className="text-xs"
            style={{ color: moodColor(item.mood) }}
            title={`已平复 ${relativeTime(new Date(item.resolvedAt))}`}
          >
            ✓ {relativeTime(new Date(item.resolvedAt))}
          </button>
        ) : (
          <button
            onClick={() => markResolved.mutate(item.id)}
            className="text-xs text-gray-400 hover:text-pink-500"
            title="标记平复"
          >
            ○
          </button>
        )}

        {/* Sub-buttons (icon-only) */}
        {!item.realityCheck && (
          <button
            onClick={() => setPendingRealityCheck(item)}
            className="text-purple-500 hover:text-purple-700"
            title="做现实检验"
          >💬</button>
        )}
        <button onClick={() => setPendingGrounding(true)} className="text-blue-500 hover:text-blue-700" title="5-4-3-2-1 grounding">👁</button>
        <button onClick={() => setPendingCompassion(true)} className="text-pink-500 hover:text-pink-700" title="自我同情">💗</button>
        <button onClick={() => setPendingCooldown(true)} className="text-purple-500 hover:text-purple-700" title="分散注意力">🔀</button>
      </div>

      {/* Trigger chips */}
      {item.triggerTags.length > 0 && (
        <div className="flex flex-wrap gap-1 mt-1">
          {item.triggerTags.slice(0, 3).map(t => (
            <span key={t} className="px-1.5 py-0 text-[10px] bg-gray-100 rounded-full">
              {TRIGGER_DISPLAY[t]}
            </span>
          ))}
          {item.triggerTags.length > 3 && (
            <span className="text-[10px] text-gray-500">+{item.triggerTags.length - 3}</span>
          )}
        </div>
      )}

      {/* Reality check inline */}
      {item.realityCheck && (
        <div className="mt-1 space-y-0.5 text-xs text-gray-600">
          <div className="flex items-center gap-1 text-purple-600 font-medium">
            <span>💬</span> 已做现实检验
          </div>
          {item.realityCheck.evidenceFor && (
            <div className="truncate">• 证据：{item.realityCheck.evidenceFor}</div>
          )}
          {item.realityCheck.evidenceAgainst && (
            <div className="truncate">• 反对：{item.realityCheck.evidenceAgainst}</div>
          )}
          {item.realityCheck.nextAction && (
            <div className="truncate">• 接下来：{item.realityCheck.nextAction}</div>
          )}
        </div>
      )}
    </div>
  )
}

// Mood color helper (mirror Rust MoodColor)
function moodColor(m: Mood): string {
  const map: Record<Mood, string> = {
    happy: '#FFC857', joyful: '#6EDC82', delighted: '#E91E63',
    sad: '#5B7A99', longing: '#9B72CF',
  }
  return map[m]
}
