import { routerReducer } from 'react-router-redux'
import { combineReducers } from 'redux'

import locale from '/layout/SelectLocale/reducer'
import notification from '/layout/Notification/reducer'
import authentication from '/layout/Authentication/reducer'
import rolesList from '/pages/Roles/List/reducers'
import editRole from '/pages/Roles/Edit/reducers'
import usersList from '/pages/Users/List/reducers'
import editUsers from '/pages/Users/Edit/reducers'
import statUnits from '/pages/StatUnits/Search/reducers'
import editStatUnit from '/pages/StatUnits/Edit/reducer'
import viewStatUnits from '/pages/StatUnits/View/reducers'
import createStatUnit from '/pages/StatUnits/Create/reducer'
import deletedStatUnits from '/pages/StatUnits/Deleted/reducer'
import createLinks from '/pages/StatUnits/Links/Create/reducers'
import deleteLinks from '/pages/StatUnits/Links/Delete/reducers'
import viewLinks from '/pages/StatUnits/Links/View/reducers'
import dataSources from '/pages/DataSources/reducer'
import dataSourcesQueue from '/pages/DataSourcesQueue/reducer'
import sampleFrames from '/pages/SampleFrames/reducer'
import analysis from '/pages/Analysis/reducer'
import reports from '/pages/Reports/reducer'

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
