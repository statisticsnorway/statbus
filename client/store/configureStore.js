import { browserHistory } from 'react-router'
import { routerMiddleware } from 'react-router-redux'
import { applyMiddleware, compose, createStore } from 'redux'
import thunkMiddleware from 'redux-thunk'
import { createLogger } from 'redux-logger'

import reduсers from './combinedReducers'

const pipeline = [thunkMiddleware, routerMiddleware(browserHistory)]
if (process.env.NODE_ENV === 'development') {
  // eslint-disable-next-line no-unused-vars
  const logger = createLogger({
    collapsed: (_, __, logEntry) => !logEntry.error,
  })
  // pipeline.push(logger)
}

export default (initialState) => {
  const store = createStore(
    reduсers,
    initialState,
    compose(
      applyMiddleware(...pipeline),
      window.devToolsExtension ? window.devToolsExtension() : _ => _,
    ),
  )
  if (module.hot) module.hot.accept('./combinedReducers', () => store.replaceReducer(reduсers))
  return store
}
