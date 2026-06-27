//! 3-tab main window content (new / stats / history)

import { useUI } from '../stores/ui'
import { NewMissingForm } from './NewMissingForm'
import { HistoryList } from './HistoryList'
import { StatisticsView } from './StatisticsView'

export function MenuBarContent() {
  const tab = useUI(s => s.tab)
  const setTab = useUI(s => s.setTab)

  return (
    <div className="h-full flex flex-col bg-white">
      {/* Tab bar */}
      <div className="flex border-b bg-gray-50">
        <TabButton active={tab === 'new'} onClick={() => setTab('new')}>新建</TabButton>
        <TabButton active={tab === 'stats'} onClick={() => setTab('stats')}>统计</TabButton>
        <TabButton active={tab === 'history'} onClick={() => setTab('history')}>历史</TabButton>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-auto">
        {tab === 'new' && <NewMissingForm />}
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
      className={`flex-1 px-4 py-2 text-sm transition-colors ${
        active
          ? 'bg-pink-50 text-pink-700 font-medium border-b-2 border-pink-500'
          : 'text-gray-600 hover:bg-gray-100'
      }`}
    >
      {children}
    </button>
  )
}
