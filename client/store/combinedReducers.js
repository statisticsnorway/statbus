import { routerReducer } from 'react-router-redux'
import { combineReducers } from 'redux'

import { reducer as locale } from 'helpers/locale'
import { reducer as status } from 'helpers/requestStatus'
import * as rolesList from '../pages/Roles/List/reducers'
import * as editRole from '../pages/Roles/Edit/reducers'
import * as usersList from '../pages/Users/List/reducers'
import * as editUsers from '../pages/Users/Edit/reducers'
import * as editAccount from '../pages/Account/Edit/reducers'
import * as statUnits from '../pages/StatUnits/Search/reducers'
import * as editStatUnits from '../pages/StatUnits/Edit/reducers'

export default combineReducers({
  routing: routerReducer,
  locale,
  status,
  ...rolesList,
  ...editRole,
  ...usersList,
  ...editUsers,
  ...editAccount,
  ...statUnits,
  ...editStatUnits,
})
