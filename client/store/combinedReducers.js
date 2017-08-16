import { routerReducer } from 'react-router-redux'
import { combineReducers } from 'redux'

import locale from 'layout/SelectLocale/reducer'
import status from 'layout/StatusBar/reducer'
import notification from 'layout/Notification/reducer'
import rolesList from 'pages/Roles/List/reducers'
import editRole from 'pages/Roles/Edit/reducers'
import usersList from 'pages/Users/List/reducers'
import editUsers from 'pages/Users/Edit/reducers'
import statUnits from 'pages/StatUnits/Search/reducers'
import editStatUnits from 'pages/StatUnits/Edit/reducer'
import viewStatUnits from 'pages/StatUnits/View/reducers'
import statUnitsCommon from 'pages/StatUnits/reducers'
import createStatUnits from 'pages/StatUnits/Create/reducer'
import deletedStatUnits from 'pages/StatUnits/Deleted/reducer'
import addressesList from 'pages/Address/List/reducers'
import regionsList from 'pages/Regions/List/reducers'
import createLinks from 'pages/StatUnits/Links/Create/reducers'
import deleteLinks from 'pages/StatUnits/Links/Delete/reducers'
import viewLinks from 'pages/StatUnits/Links/View/reducers'
import dataSources from 'pages/DataSources/reducer'
import dataSourcesQueue from 'pages/DataSourcesQueue/reducer'
import inconsistentRecords from 'pages/LogicalChecks/List/reducers'

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
  ...viewStatUnits,
  ...statUnitsCommon,
  createStatUnits,
  editStatUnits,
  deletedStatUnits,
  ...addressesList,
  ...regionsList,
  ...createLinks,
  ...deleteLinks,
  ...viewLinks,
  dataSources,
  dataSourcesQueue,
  ...inconsistentRecords,
})
