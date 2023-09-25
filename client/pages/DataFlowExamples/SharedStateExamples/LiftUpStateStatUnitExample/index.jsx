import React, { useState } from 'react'

function LiftUpStateStatUnitParent() {
  const [legalUnitId, setLegalUnitId] = useState(3)
  const [showLegalUnit, setShowLegalUnit] = useState(false)
  const [showLocalUnit, setShowLocalUnit] = useState(false)

  const setLegalUnit = () => {
    setShowLegalUnit(true)
    setShowLocalUnit(false)
  }

  const setLocalUnit = () => {
    setShowLocalUnit(true)
    setShowLegalUnit(false)
  }

  return (
    <div>
      <h1>Lift up state example</h1>
      <h3>Stat unit types</h3>
      <div>
        <button onClick={setLegalUnit}>Legal unit</button>
        <button onClick={setLocalUnit}>Local unit</button>
      </div>
      <br />

      <div>
        {showLegalUnit && <LegalUnit legalUnitId={legalUnitId} setLegalUnitId={setLegalUnitId} />}
        {showLocalUnit && <LocalUnit legalUnitId={legalUnitId} setLegalUnitId={setLegalUnitId} />}
      </div>
    </div>
  )
}

function LegalUnit({ legalUnitId, setLegalUnitId }) {
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

function LocalUnit({ legalUnitId, setLegalUnitId }) {
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

export default LiftUpStateStatUnitParent
