import { useUI } from './stores/ui'
import { MenuBarContent } from './views/MenuBarContent'
import { PopoverContent } from './views/PopoverContent'
import { RealityCheckSheet } from './sheets/RealityCheckSheet'
import { GroundingSheet } from './sheets/GroundingSheet'
import { SelfCompassionView } from './sheets/SelfCompassionView'
import { CooldownSheet } from './sheets/CooldownSheet'

export function App() {
  const view = useUI(s => s.view)
  const pendingGrounding = useUI(s => s.pendingGrounding)
  const pendingCompassion = useUI(s => s.pendingCompassion)
  const pendingCooldown = useUI(s => s.pendingCooldown)

  return (
    <>
      {view === 'popover' ? <PopoverContent /> : <MenuBarContent />}
      {/* Sheets mounted globally so any view can trigger them */}
      <RealityCheckSheet />
      {pendingGrounding && <GroundingSheet />}
      {pendingCompassion && <SelfCompassionView />}
      {pendingCooldown && <CooldownSheet />}
    </>
  )
}
