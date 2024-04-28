import React from 'react'
import { compose, withState, withHandlers, branch, renderComponent } from 'recompose'

const RecomposeFlowExample = ({
  legalUnitId,
  legalUnitName,
  localUnitId,
  localUnitName,
  showLegalUnit,
  showLocalUnit,
  setLegalUnit,
  setLocalUnit,
  setLegalUnitId,
}) => (
  <div>
    <h1>Recompose flow example</h1>
    <h3>Stat unit types</h3>
    <div>
      <button onClick={setLegalUnit}>Legal unit</button>
      <button onClick={setLocalUnit}>Local unit</button>
    </div>
    <br />

    {showLegalUnit && (
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
    )}
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
          <input type="text" value={legalUnitId} onChange={ev => setLegalUnitId(ev.target.value)} />
        </div>
      </div>
    )}
  </div>
)

export default compose(
  withState('legalUnitId', 'setLegalUnitId', 3),
  withState('legalUnitName', 'setLegalUnitName', 'LegalUnitName'),
  withState('localUnitId', 'setLocalUnitId', '5'),
  withState('localUnitName', 'setLocalUnitName', 'LocalUnitName'),
  withState('showLegalUnit', 'setShowLegalUnit', false),
  withState('showLocalUnit', 'setShowLocalUnit', false),
  withHandlers({
    setLegalUnit: ({ setShowLegalUnit, setShowLocalUnit }) => () => {
      setShowLegalUnit(true)
      setShowLocalUnit(false)
    },
    setLocalUnit: ({ setShowLocalUnit, setShowLegalUnit }) => () => {
      setShowLocalUnit(true)
      setShowLegalUnit(false)
    },
  }),
  branch(
    ({ showLegalUnit, showLocalUnit }) => false,
    renderComponent(() => null),
  ),
)(RecomposeFlowExample)
