import React, { useState } from 'react'

function LiftUpStateWithHooksParent() {
  const [state, setState] = useState('Initial state')

  return (
    <div>
      <LiftUpStateChildA state={state} setState={setState} />
      <LiftUpStateChildB state={state} setState={setState} />
    </div>
  )
}

function LiftUpStateChildA({ state, setState }) {
  return (
    <div>
      <h2>Component child A</h2>
      <p>Shared State: {state}</p>
      <button onClick={() => setState('Updated by Component child A')}>Update State</button>
    </div>
  )
}

function LiftUpStateChildB({ state, setState }) {
  return (
    <div>
      <h2>Component child B</h2>
      <p>Shared State: {state}</p>
      <button onClick={() => setState('Updated by Component child B')}>Update State</button>
    </div>
  )
}

export default LiftUpStateWithHooksParent
