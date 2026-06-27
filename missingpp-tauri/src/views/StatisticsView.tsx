//! Statistics — 3 insight cards (浪都过去了 / 常见 trigger / 现实检验完成度) + 30-day chart

import { useMemo } from 'react'
import { useRecords } from '../ipc/queries'
import { bucketFor } from '../domain/bucket'
import { TRIGGER_LABEL } from '../domain/model'
import type { Missing, TriggerTag } from '../domain/model'

export function StatisticsView() {
  const { data: items = [] } = useRecords()

  const last30 = useMemo(() => {
    const cutoff = Date.now() - 30 * 86400000
    return items.filter(i => new Date(i.createdAt).getTime() >= cutoff)
  }, [items])

  // Wave stats
  const wave = useMemo(() => {
    const total = last30.length
    if (total === 0) return { rate: 0, count: 0, total: 0, avg: null as number | null }
    const durations = last30
      .filter(i => i.resolvedAt)
      .map(i => (new Date(i.resolvedAt!).getTime() - new Date(i.createdAt).getTime()) / 1000)
    const count = durations.length
    const avg = durations.length > 0 ? durations.reduce((a, b) => a + b, 0) / durations.length : null
    return { rate: count / total, count, total, avg }
  }, [last30])

  // Top triggers
  const topTriggers = useMemo(() => {
    const total = last30.length
    if (total === 0) return []
    const counts: Record<string, number> = {}
    for (const item of last30) {
      for (const t of item.triggerTags) {
        counts[t] = (counts[t] || 0) + 1
      }
    }
    return Object.entries(counts)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 3)
      .map(([t, c]) => ({ tag: t as TriggerTag, count: c, total }))
  }, [last30])

  // Reality check stats
  const rcStats = useMemo(() => {
    const eligible = last30.filter(i => i.intensity === 'strong').length
    if (eligible === 0) return { rate: 0, completed: 0, eligible: 0 }
    const completed = last30.filter(i => i.intensity === 'strong' && i.realityCheck).length
    return { rate: completed / eligible, completed, eligible }
  }, [last30])

  return (
    <div className="p-3 space-y-3">
      <SectionHeader icon="📊" title="统计" />

      <div className="grid grid-cols-3 gap-2 text-sm">
        <SummaryStat label="累计思念" value={`${items.length} 条`} />
        <SummaryStat label="本周新增" value={`${last30.filter(i => bucketFor(new Date(i.createdAt)) === 'thisWeek').length} 条`} />
        <SummaryStat label="平复率" value={
          items.length === 0 ? '—' :
          `${Math.round(items.filter(i => i.resolvedAt).length / items.length * 100)}%`
        } />
      </div>

      <InsightCard
        title="浪都过去了"
        big={`${Math.round(wave.rate * 100)}%`}
        sub={wave.total === 0 ? '还没有记录' :
             wave.avg === null ? `${wave.count} / ${wave.total} 次平复` :
             formatAvg(wave.avg, wave.count, wave.total)
        }
        color="pink"
      />

      <TopTriggersCard triggers={topTriggers} />
      <RealityCheckCard stats={rcStats} />

      <div className="pt-2">
        <p className="text-xs text-gray-500">近 30 天</p>
        <MiniChart items={last30} />
      </div>
    </div>
  )
}

function formatAvg(seconds: number, count: number, total: number): string {
  const hours = seconds / 3600
  if (hours < 1) return `${count}/${total} 次平复 · 平均 ${Math.round(seconds / 60)} 分钟`
  if (hours < 48) return `${count}/${total} 次平复 · 平均 ${hours.toFixed(1)} 小时`
  return `${count}/${total} 次平复 · 平均 ${(hours / 24).toFixed(1)} 天`
}

function SectionHeader({ icon, title }: { icon: string; title: string }) {
  return (
    <div className="flex items-center gap-2">
      <span className="text-pink-500">{icon}</span>
      <span className="font-medium">{title}</span>
    </div>
  )
}

function SummaryStat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-xs text-gray-500">{label}</div>
      <div className="text-sm font-medium">{value}</div>
    </div>
  )
}

function InsightCard({ title, big, sub, color }: {
  title: string; big: string; sub: string; color: 'pink' | 'gray' | 'purple'
}) {
  const bg = { pink: 'bg-pink-50', gray: 'bg-gray-50', purple: 'bg-purple-50' }[color]
  return (
    <div className={`p-3 ${bg} rounded-md`}>
      <div className="text-sm font-medium">{title}</div>
      <div className="text-3xl font-semibold mt-1" style={{ fontVariantNumeric: 'tabular-nums' }}>
        {big}
        <span className="text-xs text-gray-500 font-normal ml-1.5">过去 30 天</span>
      </div>
      <div className="text-xs text-gray-500 mt-1">{sub}</div>
    </div>
  )
}

function TopTriggersCard({ triggers }: {
  triggers: { tag: TriggerTag; count: number; total: number }[]
}) {
  if (triggers.length === 0) {
    return (
      <div className="p-3 bg-gray-50 rounded-md">
        <div className="text-sm font-medium">你的常见 trigger</div>
        <div className="text-xs text-gray-500 mt-1">记几次带 trigger 标签的想念后会看到</div>
      </div>
    )
  }
  return (
    <div className="p-3 bg-gray-50 rounded-md">
      <div className="text-sm font-medium mb-2">你的常见 trigger</div>
      {triggers.map(({ tag, count, total }) => (
        <div key={tag} className="mb-2 last:mb-0">
          <div className="flex items-center justify-between text-sm">
            <span>{TRIGGER_LABEL[tag]}</span>
            <span className="text-xs text-gray-500">{count} 次 · {Math.round(count / total * 100)}%</span>
          </div>
          <div className="h-1 bg-pink-200 rounded mt-1 overflow-hidden">
            <div className="h-full bg-pink-500" style={{ width: `${(count / total) * 100}%` }} />
          </div>
        </div>
      ))}
    </div>
  )
}

function RealityCheckCard({ stats }: { stats: { rate: number; completed: number; eligible: number } }) {
  if (stats.eligible === 0) {
    return (
      <div className="p-3 bg-purple-50 rounded-md">
        <div className="text-sm font-medium">现实检验完成度</div>
        <div className="text-xs text-gray-500 mt-1">还没有强烈的想念需要检验</div>
      </div>
    )
  }
  return (
    <div className="p-3 bg-purple-50 rounded-md">
      <div className="text-sm font-medium">现实检验完成度</div>
      <div className="text-xl font-semibold mt-1">
        {Math.round(stats.rate * 100)}%
        <span className="text-xs text-gray-500 font-normal ml-1.5">强烈的想念里</span>
      </div>
      <div className="text-xs text-gray-500 mt-1">
        {stats.completed} / {stats.eligible} 次完成 DBT Check the Facts
      </div>
    </div>
  )
}

function MiniChart({ items }: { items: Missing[] }) {
  // Build 30-day buckets
  const days = 30
  const buckets: Record<number, number> = {}
  for (let i = 0; i < days; i++) buckets[i] = 0
  const now = Date.now()
  for (const item of items) {
    const dayIndex = days - 1 - Math.floor((now - new Date(item.createdAt).getTime()) / 86400000)
    if (dayIndex >= 0 && dayIndex < days) {
      buckets[dayIndex] = (buckets[dayIndex] || 0) + 1
    }
  }
  const max = Math.max(1, ...Object.values(buckets))
  return (
    <div className="flex items-end gap-0.5 h-24 mt-2">
      {Object.values(buckets).map((c, i) => (
        <div
          key={i}
          className="flex-1 bg-pink-300 rounded-t"
          style={{ height: `${(c / max) * 100}%` }}
          title={`${c} 条`}
        />
      ))}
    </div>
  )
}
