import React, { useState } from 'react'

// Parent Component
function LiftUpStateParent() {
  const [sharedState, setSharedState] = useState('Initial state')

  return (
    <div>
      <LiftUpStateChildA state={sharedState} setState={setSharedState} />
      <LiftUpStateChildB state={sharedState} setState={setSharedState} />
    </div>
  )
}

// Child Component A
function LiftUpStateChildA({ state, setState }) {
  return (
    <div>
      <h2>Component child A</h2>
      <p>Shared State: {state}</p>
      <button onClick={() => setState('Updated by Component child A')}>Update State</button>
    </div>
  )
}

// Child Component B
function LiftUpStateChildB({ state, setState }) {
  return (
    <div>
      <h2>Component child B</h2>
      <p>Shared State: {state}</p>
      <button onClick={() => setState('Updated by Component child B')}>Update State</button>
    </div>
  )
}

export default LiftUpStateParent
