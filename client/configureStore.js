import { applyMiddleware, compose, createStore } from 'redux'
import thunkMiddleware from 'redux-thunk'

import redcuers from './combinedReducers'

export default (initialState) => {
  const store = createStore(
    redcuers,
    initialState,
    compose(
      applyMiddleware(thunkMiddleware),
      window.devToolsExtension ? window.devToolsExtension() : f => f
    )
  )

  if (module.hot) module.hot.accept('./combinedReducers', () => store.replaceReducer(redcuers))

  return store
}
