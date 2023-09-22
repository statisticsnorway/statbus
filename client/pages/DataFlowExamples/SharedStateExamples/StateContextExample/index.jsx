import React, { useContext, useState } from 'react'

const StateContext = React.createContext()

function StateContextParent() {
  const [state, setState] = useState('Initial state')

  return (
    <StateContext.Provider value={{ state, setState }}>
      <ParentA />
      <StateContextChildB />
    </StateContext.Provider>
  )
}

function ParentA() {
  return (
    <div>
      <p>Inside parent A</p>
      <StateContextChildA />
    </div>
  )
}

function StateContextChildA() {
  const { state, setState } = useContext(StateContext)

  return (
    <div>
      <p>State from Context: {state}</p>
      <button onClick={() => setState('Updated by Component child A')}>Update</button>
    </div>
  )
}

function StateContextChildB() {
  const { state, setState } = useContext(StateContext)

  return (
    <div>
      <p>State from Context: {state}</p>
      <button onClick={() => setState('Updated by Component child B')}>Update</button>
    </div>
  )
}

export default StateContextParent
