import { routerReducer } from 'react-router-redux'
import { combineReducers } from 'redux'

import locale from '/client/layout/SelectLocale/reducer'
import notification from '/client/layout/Notification/reducer'
import authentication from '/client/layout/Authentication/reducer'
import rolesList from '/client/pages/Roles/List/reducers'
import editRole from '/client/pages/Roles/Edit/reducers'
import usersList from '/client/pages/Users/List/reducers'
import editUsers from '/client/pages/Users/Edit/reducers'
import statUnits from '/client/pages/StatUnits/Search/reducers'
import editStatUnit from '/client/pages/StatUnits/Edit/reducer'
import viewStatUnits from '/client/pages/StatUnits/View/reducers'
import createStatUnit from '/client/pages/StatUnits/Create/reducer'
import deletedStatUnits from '/client/pages/StatUnits/Deleted/reducer'
import createLinks from '/client/pages/StatUnits/Links/Create/reducers'
import deleteLinks from '/client/pages/StatUnits/Links/Delete/reducers'
import viewLinks from '/client/pages/StatUnits/Links/View/reducers'
import dataSources from '/client/pages/DataSources/reducer'
import dataSourcesQueue from '/client/pages/DataSourcesQueue/reducer'
import sampleFrames from '/client/pages/SampleFrames/reducer'
import analysis from '/client/pages/Analysis/reducer'
import reports from '/client/pages/Reports/reducer'

export default combineReducers({
  ...rolesList,
  ...editRole,
  ...usersList,
  ...editUsers,
  ...statUnits,
  ...viewStatUnits,
  ...createLinks,
  ...deleteLinks,
  ...viewLinks,
  routing: routerReducer,
  locale,
  notification,
  authentication,
  createStatUnit,
  editStatUnit,
  deletedStatUnits,
  dataSources,
  dataSourcesQueue,
  sampleFrames,
  analysis,
  reports,
})
