import { routerReducer } from 'react-router-redux'
import { combineReducers } from 'redux'

import { reducer as locale } from 'helpers/locale'
import { reducer as status } from 'helpers/requestStatus'
import rolesList from '../pages/Roles/List/reducers'
import editRole from '../pages/Roles/Edit/reducers'
import usersList from '../pages/Users/List/reducers'
import editUsers from '../pages/Users/Edit/reducers'
import editAccount from '../pages/Account/Edit/reducers'
import statUnits from '../pages/StatUnits/Search/reducers'
import editStatUnits from '../pages/StatUnits/Edit/reducers'
import viewStatUnits from '../pages/StatUnits/View/reducers'
import statUnitsCommon from '../pages/StatUnits/reducers'
import createStatUnits from '../pages/StatUnits/Create/reducers'
import regionsList from '../pages/Regions/List/reducers'

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
  ...viewStatUnits,
  ...statUnitsCommon,
  ...createStatUnits,
  ...regionsList,
})
