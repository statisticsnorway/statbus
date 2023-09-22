import React, { useContext, useState } from 'react'

const SharedStateContext = React.createContext()

function ParentComponent() {
  const [sharedState, setSharedState] = useState('Initial state')

  return (
    <SharedStateContext.Provider value={{ sharedState, setSharedState }}>
      <ChildComponentA />
      <ChildComponentB />
    </SharedStateContext.Provider>
  )
}

function ChildComponentA() {
  const { sharedState, setSharedState } = useContext(SharedStateContext)

  return (
    <div>
      <p>State from Context: {sharedState}</p>
      <button onClick={() => setSharedState('Updated by A')}>Update</button>
    </div>
  )
}

function ChildComponentB() {
  const { sharedState, setSharedState } = useContext(SharedStateContext)

  // Similar code to ChildComponentA...
}

function useSharedState() {
  const [state, setState] = useState('Initial state')
  // ... other shared logic

  return [state, setState]
}

function ComponentA() {
  const [state, setState] = useSharedState()
  // ... use state as needed
}

function ComponentB() {
  const [state, setState] = useSharedState()
  // ... use state as needed
}
