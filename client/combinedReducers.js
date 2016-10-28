import { routerReducer } from 'react-router-redux'
import { combineReducers } from 'redux'

import * as homeReducers from './views/Home/reducers'

export default combineReducers({
  routing: routerReducer,
  ...homeReducers,
})
