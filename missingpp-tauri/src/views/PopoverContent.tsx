//! 2-tab popover content (stat / history) — kept lean for peek UX

import { useUI } from '../stores/ui'
import { HistoryList } from './HistoryList'
import { StatisticsView } from './StatisticsView'

export function PopoverContent() {
  const tab = useUI(s => s.tab)
  const setTab = useUI(s => s.setTab)

  return (
    <div className="h-full flex flex-col bg-white">
      <div className="flex border-b bg-gray-50">
        <TabButton active={tab === 'stats'} onClick={() => setTab('stats')}>统计</TabButton>
        <TabButton active={tab === 'history'} onClick={() => setTab('history')}>历史</TabButton>
      </div>
      <div className="flex-1 overflow-auto">
        {tab === 'stats' && <StatisticsView />}
        {tab === 'history' && <HistoryList />}
      </div>
    </div>
  )
}

function TabButton({ active, onClick, children }: {
  active: boolean; onClick: () => void; children: React.ReactNode
}) {
  return (
    <button
      onClick={onClick}
      className={`flex-1 px-3 py-2 text-sm transition-colors ${
        active
          ? 'bg-pink-50 text-pink-700 font-medium border-b-2 border-pink-500'
          : 'text-gray-600 hover:bg-gray-100'
      }`}
    >
      {children}
    </button>
  )
}
