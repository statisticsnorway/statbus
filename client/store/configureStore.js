import { browserHistory } from 'react-router'
import { routerMiddleware } from 'react-router-redux'
import { applyMiddleware, compose, createStore } from 'redux'
import thunkMiddleware from 'redux-thunk'

import redcuers from './combinedReducers'

export default (initialState) => {
  const store = createStore(
    redcuers,
    initialState,
    compose(
      applyMiddleware(
        thunkMiddleware,
        routerMiddleware(browserHistory),
      ),
      window.devToolsExtension ? window.devToolsExtension() : f => f,
    ),
  )
  if (module.hot) module.hot.accept('./combinedReducers', () => store.replaceReducer(redcuers))
  return store
}
