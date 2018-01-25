import React from 'react'
import { IndexRoute, Route, Redirect } from 'react-router'

import { checkSystemFunction as sF } from 'helpers/config'
import Layout from 'layout'
import About from 'pages/About'
import NotFound from 'pages/NotFound'
import AccountView from 'pages/Account/View'
import AccountEdit from 'pages/Account/Edit'
import StatUnitSearch from 'pages/StatUnits/Search'
import StatUnitView from 'pages/StatUnits/View'
import StatUnitEdit from 'pages/StatUnits/Edit'
import StatUnitCreate from 'pages/StatUnits/Create'
import StatUnitDeletedList from 'pages/StatUnits/Deleted'
import SampleFramesList from 'pages/SampleFrames/List'
import SampleFramesCreate from 'pages/SampleFrames/Create'
import SampleFramesEdit from 'pages/SampleFrames/Edit'
import SampleFramesPreview from 'pages/SampleFrames/Preview'
import AnalysisQueue from 'pages/Analysis/Queue'
import AnalysisCreate from 'pages/Analysis/Create'
import AnalysisLogs from 'pages/Analysis/AnalysisLogs'
import AnalysisLogDetails from 'pages/Analysis/Details'
import DataSourcesQueueList from 'pages/DataSourcesQueue/List'
import DataSourcesQueueLog from 'pages/DataSourcesQueue/QueueLog'
import DataSourcesQueueLogDetails from 'pages/DataSourcesQueue/LogDetails'
import ReportsTree from 'pages/Reports'

import StatUnitLinksRoutes from 'pages/StatUnits/Links/Routes'
import RolesRoutes from 'pages/Roles/Routes'
import UsersRoutes from 'pages/Users/Routes'
import DataSourcesRoutes from 'pages/DataSources/Routes'

export default (
  <Route path="/" component={Layout}>
    <IndexRoute component={StatUnitSearch} />
    <Redirect from="/statunits" to="/" />
    <Redirect from="statunits/create" to="statunits/create/1" />
    <Route path="about" component={About} />
    <Route path="account" component={AccountView} />
    <Route path="account/edit" component={AccountEdit} />
    <Route path="statunits">
      <Route path="view/:type/:id" component={StatUnitView} />
      {sF('StatUnitCreate') && (
        <Route path="create">
          <Route path=":type" component={StatUnitCreate} />
        </Route>
      )}
      {sF('StatUnitEdit') && <Route path="edit/:type/:id" component={StatUnitEdit} />}
      {sF('StatUnitDelete') && <Route path="deleted" component={StatUnitDeletedList} />}
      {StatUnitLinksRoutes}
    </Route>
    {sF('SampleFramesView') && (
      <Route path="sampleframes">
        <IndexRoute component={SampleFramesList} />
        <Redirect from="list" to="/" />
        {sF('SampleFramesPreview') && <Route path="preview/:id" component={SampleFramesPreview} />}
        {sF('SampleFramesCreate') && <Route path="create" component={SampleFramesCreate} />}
        {sF('SampleFramesEdit') && <Route path=":id" component={SampleFramesEdit} />}
      </Route>
    )}
    {sF('AnalysisQueueView') && (
      <Route path="analysisqueue">
        <IndexRoute component={AnalysisQueue} />
        <Redirect from="list" to="/" />
        <Route path="create" component={AnalysisCreate} />
        <Route path=":queueId/log" component={AnalysisLogs} />
        <Route path=":queueId/log/:logId" component={AnalysisLogDetails} />
      </Route>
    )}
    {sF('RoleView') && RolesRoutes}
    {sF('UserView') && UsersRoutes}
    {sF('DataSourcesView') && DataSourcesRoutes}
    {sF('DataSourcesQueueView') && (
      <Route path="datasourcesqueue">
        <IndexRoute component={DataSourcesQueueList} />
        <Route path=":id/log" component={DataSourcesQueueLog} />
        <Route path=":queueId/log/:logId" component={DataSourcesQueueLogDetails} />
      </Route>
    )}
    <Route path="reportsTree" component={ReportsTree} />
    <Route path="*" component={NotFound} />
  </Route>
)
