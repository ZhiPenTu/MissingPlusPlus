//! Date grouping helpers

export type DateBucket = 'today' | 'yesterday' | 'thisWeek' | 'thisMonth' | 'earlier'

export const BUCKET_LABEL: Record<DateBucket, string> = {
  today: '今天',
  yesterday: '昨天',
  thisWeek: '本周',
  thisMonth: '本月',
  earlier: '更早',
}

export function bucketFor(date: Date, now: Date = new Date()): DateBucket {
  const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate())
  const today = startOfDay(now)
  const yesterday = new Date(today.getTime() - 86400000)
  const weekAgo = new Date(today.getTime() - 7 * 86400000)
  const monthAgo = new Date(today.getTime() - 30 * 86400000)
  const day = startOfDay(date)
  if (day.getTime() === today.getTime()) return 'today'
  if (day.getTime() === yesterday.getTime()) return 'yesterday'
  if (day.getTime() >= weekAgo.getTime()) return 'thisWeek'
  if (day.getTime() >= monthAgo.getTime()) return 'thisMonth'
  return 'earlier'
}

export function relativeTime(date: Date, now: Date = new Date()): string {
  const diff = now.getTime() - date.getTime()
  if (diff < 60000) return '刚刚'
  if (diff < 3600000) return `${Math.floor(diff / 60000)} 分钟前`
  if (diff < 86400000) return `${Math.floor(diff / 3600000)} 小时前`
  if (diff < 30 * 86400000) return `${Math.floor(diff / 86400000)} 天前`
  if (diff < 365 * 86400000) return `${Math.floor(diff / (30 * 86400000))} 个月前`
  return `${Math.floor(diff / (365 * 86400000))} 年前`
}
