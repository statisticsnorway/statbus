import { routerReducer } from 'react-router-redux'
import { applyMiddleware, compose, createStore, combineReducers } from 'redux'
import thunkMiddleware from 'redux-thunk'

import * as homeReducers from './views/Home/reducers'

export default initialState => createStore(
  combineReducers({
    routing: routerReducer,
    ...homeReducers,
  }),
  initialState,
  compose(
    applyMiddleware(thunkMiddleware),
    window.devToolsExtension ? window.devToolsExtension() : f => f
  )
)
