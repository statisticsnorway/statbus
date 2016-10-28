import { routerReducer } from 'react-router-redux'
import { combineReducers } from 'redux'
import * as home from './views/Home/reducers'
import * as rolesList from './views/Roles/List/reducers'
import * as createRole from './views/Roles/Create/reducers'

export default combineReducers({
  routing: routerReducer,
  ...home,
  ...rolesList,
  ...createRole,
})
