import { routerReducer } from 'react-router-redux'
import { combineReducers } from 'redux'
import * as rolesList from './pages/Roles/List/reducers'
import * as createRole from './pages/Roles/Create/reducers'
import * as editRole from './pages/Roles/Edit/reducers'
import * as usersList from './pages/Users/List/reducers'
import * as createUsers from './pages/Users/Create/reducers'
import * as editUsers from './pages/Users/Edit/reducers'

export default combineReducers({
  routing: routerReducer,
  ...rolesList,
  ...createRole,
  ...editRole,
  ...usersList,
  ...createUsers,
  ...editUsers,
})
