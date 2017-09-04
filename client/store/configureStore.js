import { browserHistory } from 'react-router'
import { routerMiddleware } from 'react-router-redux'
import { applyMiddleware, compose, createStore } from 'redux'
import thunkMiddleware from 'redux-thunk'
import { createLogger } from 'redux-logger'

import redcuers from './combinedReducers'

const pipeline = [
  thunkMiddleware,
  routerMiddleware(browserHistory),
]
if (process.env.NODE_ENV === 'development') {
  const options = {
    collapsed: (_, __, logEntry) => !logEntry.error,
  }
  pipeline.push(createLogger(options))
}

export default (initialState) => {
  const store = createStore(
    redcuers,
    initialState,
    compose(
      applyMiddleware(...pipeline),
      window.devToolsExtension ? window.devToolsExtension() : () => { },
    ),
  )
  if (module.hot) module.hot.accept('./combinedReducers', () => store.replaceReducer(redcuers))
  return store
}
