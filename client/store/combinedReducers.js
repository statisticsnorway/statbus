import { routerReducer } from 'react-router-redux'
import { combineReducers } from 'redux'

import { reducer as locale } from 'helpers/locale'
import { reducer as status } from 'helpers/requestStatus'
import { reducer as notification } from 'helpers/notification'
import rolesList from '../pages/Roles/List/reducers'
import editRole from '../pages/Roles/Edit/reducers'
import usersList from '../pages/Users/List/reducers'
import editUsers from '../pages/Users/Edit/reducers'
import statUnits from '../pages/StatUnits/Search/reducers'
import editStatUnits from '../pages/StatUnits/Edit/reducers'
import viewStatUnits from '../pages/StatUnits/View/reducers'
import statUnitsCommon from '../pages/StatUnits/reducers'
import createStatUnits from '../pages/StatUnits/Create/reducers'
import deletedStatUnits from '../pages/StatUnits/Deleted/reducers'
import regionsList from '../pages/Regions/List/reducers'
import addressesList from '../pages/Address/List/reducers'
import soatesList from '../pages/Soates/List/reducers'
import createLinks from '../pages/StatUnits/Links/Create/reducers'
import deleteLinks from '../pages/StatUnits/Links/Delete/reducers'
import viewLinks from '../pages/StatUnits/Links/View/reducers'
import dataSources from '../pages/DataSources/reducer'
import dataSourceQueues from '../pages/DataSourceQueues/reducers'
import inconsistentRecords from '../pages/LogicalChecks/List/reducers'

export default combineReducers({
  routing: routerReducer,
  locale,
  status,
  notification,
  ...rolesList,
  ...editRole,
  ...usersList,
  ...editUsers,
  ...statUnits,
  ...editStatUnits,
  ...viewStatUnits,
  ...statUnitsCommon,
  ...createStatUnits,
  ...deletedStatUnits,
  ...regionsList,
  ...addressesList,
  ...soatesList,
  ...createLinks,
  ...deleteLinks,
  ...viewLinks,
  dataSources,
  ...dataSourceQueues,
  ...inconsistentRecords,
})
