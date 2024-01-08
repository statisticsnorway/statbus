import React, { useContext, useState } from 'react'

const StateContext = React.createContext()

function StateContextWithHooksParent() {
  const [state, setState] = useState('Initial state')

  return (
    <StateContext.Provider value={{ state, setState }}>
      <ParentA />
      <StateContextWithHooksChildB />
    </StateContext.Provider>
  )
}

function ParentA() {
  return (
    <div>
      <p>Inside parent A</p>
      <StateContextWithHooksChildA />
    </div>
  )
}

function StateContextWithHooksChildA() {
  const { state, setState } = useContext(StateContext)

  return (
    <div>
      <p>State from Context: {state}</p>
      <button onClick={() => setState('Updated by Component child A')}>Update</button>
    </div>
  )
}

function StateContextWithHooksChildB() {
  const { state, setState } = useContext(StateContext)

  return (
    <div>
      <p>State from Context: {state}</p>
      <button onClick={() => setState('Updated by Component child B')}>Update</button>
    </div>
  )
}

export default StateContextWithHooksParent
