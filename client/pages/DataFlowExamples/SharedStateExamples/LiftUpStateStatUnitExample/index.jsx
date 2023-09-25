import React, { useState } from 'react'

function LiftUpStateStatUnitParent() {
  const [legalUnitId, setLegalUnitId] = useState(3)
  const [legalUnitName] = useState('LegalUnitName')
  const [localUnitId] = useState('5')
  const [localUnitName] = useState('LocalUnitName')
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
        <LiftUpStateLegalUnitChild
          legalUnitId={legalUnitId}
          legalUnitName={legalUnitName}
          setLegalUnitId={setLegalUnitId}
          showLegalUnit={showLegalUnit}
        />
        <LiftUpStateLocalUnitChild
          localUnitId={localUnitId}
          localUnitName={localUnitName}
          legalUnitId={legalUnitId}
          setLegalUnitId={setLegalUnitId}
          showLocalUnit={showLocalUnit}
        />
      </div>
    </div>
  )
}

function LiftUpStateLegalUnitChild({ legalUnitId, legalUnitName, setLegalUnitId, showLegalUnit }) {
  return (
    <div>
      {showLegalUnit && (
        <div>
          <strong>Legal unit</strong>
          <div>
            ID:
            <br />
            <input
              type="text"
              value={legalUnitId}
              onChange={ev => setLegalUnitId(ev.target.value)}
            />
            <br />
            Name:
            <br />
            <input type="text" value={legalUnitName} readOnly />
          </div>
        </div>
      )}
    </div>
  )
}

function LiftUpStateLocalUnitChild({
  localUnitId,
  localUnitName,
  legalUnitId,
  setLegalUnitId,
  showLocalUnit,
}) {
  return (
    <div>
      {showLocalUnit && (
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
            <input
              type="text"
              value={legalUnitId}
              onChange={ev => setLegalUnitId(ev.target.value)}
            />
          </div>
        </div>
      )}
    </div>
  )
}

export default LiftUpStateStatUnitParent
