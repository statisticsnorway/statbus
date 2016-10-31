import { routerReducer } from 'react-router-redux'
import { combineReducers } from 'redux'
import * as home from './pages/Home/reducers'
import * as rolesList from './pages/Roles/List/reducers'
import * as createRole from './pages/Roles/Create/reducers'
import * as editRole from './pages/Roles/Edit/reducers'

export default combineReducers({
  routing: routerReducer,
  ...home,
  ...rolesList,
  ...createRole,
  ...editRole,
})
