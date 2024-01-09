import React, { useContext, useState } from 'react'

const StateContext = React.createContext()

function StateContextWithHooksStatUnitParent() {
  const [legalUnitId, setLegalUnitId] = useState(3)
  const [showLegalUnit, setShowLegalUnit] = useState(false)
  const [showLocalUnit, setShowLocalUnit] = useState(false)

  const switchToLegalUnit = () => {
    setShowLegalUnit(true)
    setShowLocalUnit(false)
  }

  const switchToLocalUnit = () => {
    setShowLocalUnit(true)
    setShowLegalUnit(false)
  }

  return (
    <div>
      <h1>State context with hooks example</h1>
      <h3>Stat unit types</h3>
      <div>
        <button onClick={switchToLegalUnit}>Legal unit</button>
        <button onClick={switchToLocalUnit}>Local unit</button>
      </div>
      <br />

      <StateContext.Provider value={{ legalUnitId, setLegalUnitId }}>
        {showLegalUnit && <LegalUnit />}
        {showLocalUnit && <LocalUnit />}
      </StateContext.Provider>
    </div>
  )
}

function LegalUnit() {
  const { legalUnitId, setLegalUnitId } = useContext(StateContext)
  const [legalUnitName] = useState('LegalUnitName')

  return (
    <div>
      <strong>Legal unit</strong>
      <div>
        ID:
        <br />
        <input type="text" value={legalUnitId} onChange={ev => setLegalUnitId(ev.target.value)} />
        <br />
        Name:
        <br />
        <input type="text" value={legalUnitName} readOnly />
      </div>
    </div>
  )
}

function LocalUnit() {
  const { legalUnitId, setLegalUnitId } = useContext(StateContext)
  const [localUnitId] = useState('5')
  const [localUnitName] = useState('LocalUnitName')
  return (
    <div>
      <strong>Local unit:</strong>
      <div>
        ID:
        <br />
        <input type="text" value={localUnitId} readOnly />
        <br />
        Name:
        <br />
        <input type="text" value={localUnitName} readOnly />
        <br />
        Legal unit ID:
        <br />
        <input type="text" value={legalUnitId} onChange={ev => setLegalUnitId(ev.target.value)} />
      </div>
    </div>
  )
}

export default StateContextWithHooksStatUnitParent
