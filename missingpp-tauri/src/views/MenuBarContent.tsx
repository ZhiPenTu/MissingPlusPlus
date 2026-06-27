//! 3-tab main window content (new / stats / history).
//! Tab bar uses the Swift app's rounded gray card + internal pill style.

import { useUI } from '../stores/ui'
import { NewMissingForm } from './NewMissingForm'
import { HistoryList } from './HistoryList'
import { StatisticsView } from './StatisticsView'

export function MenuBarContent() {
  const tab = useUI(s => s.tab)
  const setTab = useUI(s => s.setTab)

  return (
    <div className="h-full flex flex-col bg-gray-100">
      <div className="px-3 py-2 bg-white border-b border-gray-200">
        <div className="flex gap-1 p-1 bg-gray-100 rounded-lg">
          <TabButton active={tab === 'new'} onClick={() => setTab('new')}>新建</TabButton>
          <TabButton active={tab === 'stats'} onClick={() => setTab('stats')}>统计</TabButton>
          <TabButton active={tab === 'history'} onClick={() => setTab('history')}>历史</TabButton>
        </div>
      </div>
      <div className="flex-1 overflow-hidden">
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
      className={`flex-1 px-3 py-1.5 text-sm rounded-md transition-colors ${
        active
          ? 'bg-white text-pink-600 font-medium shadow-sm'
          : 'text-gray-500 hover:text-gray-700'
      }`}
    >
      {children}
    </button>
  )
}
