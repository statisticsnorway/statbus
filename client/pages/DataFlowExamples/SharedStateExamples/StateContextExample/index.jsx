import React, { useContext, useState } from 'react'

const SharedStateContext = React.createContext()

function StateContextParent() {
  const [sharedState, setSharedState] = useState('Initial state')

  return (
    <SharedStateContext.Provider value={{ sharedState, setSharedState }}>
      <StateContextChildA />
      <StateContextChildB />
    </SharedStateContext.Provider>
  )
}

function StateContextChildA() {
  const { sharedState, setSharedState } = useContext(SharedStateContext)

  return (
    <div>
      <p>State from Context: {sharedState}</p>
      <button onClick={() => setSharedState('Updated by Component child A')}>Update</button>
    </div>
  )
}

function StateContextChildB() {
  const { sharedState, setSharedState } = useContext(SharedStateContext)

  return (
    <div>
      <p>State from Context: {sharedState}</p>
      <button onClick={() => setSharedState('Updated by Component child B')}>Update</button>
    </div>
  )
}

export default StateContextParent
