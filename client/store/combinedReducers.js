import { routerReducer } from 'react-router-redux'
import { combineReducers } from 'redux'

import { reducer as status } from '../helpers/requestStatus'
import * as rolesList from '../pages/Roles/List/reducers'
import * as editRole from '../pages/Roles/Edit/reducers'
import * as usersList from '../pages/Users/List/reducers'
import * as editUsers from '../pages/Users/Edit/reducers'
import * as editAccount from '../pages/Account/Edit/reducers'

export default combineReducers({
  routing: routerReducer,
  status,
  ...rolesList,
  ...editRole,
  ...usersList,
  ...editUsers,
  ...editAccount,
})
