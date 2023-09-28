import React from 'react'
import { IndexRoute, Route, Redirect } from 'react-router'

import { checkSystemFunction as sF } from '/client/helpers/config'
import Layout from '/client/layout'
import About from '/client/pages/About'
import NotFound from '/client/pages/NotFound'
import AccountView from '/client/pages/Account/View'
import AccountEdit from '/client/pages/Account/Edit'
import StatUnitSearch from '/client/pages/StatUnits/Search'
import StatUnitView from '/client/pages/StatUnits/View'
import StatUnitEdit from '/client/pages/StatUnits/Edit'
import StatUnitCreate from '/client/pages/StatUnits/Create'
import StatUnitDeletedList from '/client/pages/StatUnits/Deleted'
import SampleFramesList from '/client/pages/SampleFrames/List'
import SampleFramesCreate from '/client/pages/SampleFrames/Create'
import SampleFramesEdit from '/client/pages/SampleFrames/Edit'
import SampleFramesPreview from '/client/pages/SampleFrames/Preview'
import AnalysisQueue from '/client/pages/Analysis/Queue'
import AnalysisCreate from '/client/pages/Analysis/Create'
import AnalysisLogs from '/client/pages/Analysis/AnalysisLogs'
import AnalysisLogDetails from '/client/pages/Analysis/Details'
import DataSourcesQueueList from '/client/pages/DataSourcesQueue/List'
import DataSourcesQueueLog from '/client/pages/DataSourcesQueue/QueueLog'
import DataSourcesQueueLogDetails from '/client/pages/DataSourcesQueue/LogDetails'
import DataSourcesQueueActivityLogDetails from '/client/pages/DataSourcesQueue/ActivityLogDetails'

import ReportsTree from '/client/pages/Reports'

import StatUnitLinksRoutes from '/client/pages/StatUnits/Links/Routes'
import RolesRoutes from '/client/pages/Roles/Routes'
import UsersRoutes from '/client/pages/Users/Routes'
import DataSourcesRoutes from '/client/pages/DataSources/Routes'
import ClassFlowExample from '/client/pages/DataFlowExamples/ClassFlowExample'
import RecomposeFlowExample from '/client/pages/DataFlowExamples/RecomposeFlowExample'
import FromRecomposeToHooksExample from '/client/pages/DataFlowExamples/HooksExamples/FromRecomposeToHooksExample'
import FromClassToHooksExample from '/client/pages/DataFlowExamples/HooksExamples/FromClassToHooksExample'
import LiftUpStateWithHooksParent from '/client/pages/DataFlowExamples/SharedStateExamples/LiftUpStateWithHooksExample'
import StateContextWithHooksParent from '/client/pages/DataFlowExamples/SharedStateExamples/StateContextWithHooksExample'
import LiftUpStateWithHooksStatUnitParent from '/client/pages/DataFlowExamples/SharedStateExamples/LiftUpStateWithHooksStatUnitExample'
import StateContextWithHooksStatUnitParent from '/client/pages/DataFlowExamples/SharedStateExamples/StateContextWithHooksStatUnitExample'
import LiftUpStateWithClassExample from '/client/pages/DataFlowExamples/SharedStateExamples/LiftUpStateWithClassExample'

export default (
  <Route path="/" component={Layout}>
    <IndexRoute component={StatUnitSearch} />
    <Redirect from="/statunits" to="/" />
    <Redirect from="statunits/create" to="statunits/create/2" />
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
        <Route
          path=":queueId/log/activity/:statId"
          component={DataSourcesQueueActivityLogDetails}
        />
      </Route>
    )}
    <Route path="classflowexample" component={ClassFlowExample} />
    <Route path="recomposeflowexample" component={RecomposeFlowExample} />
    <Route
      path="hooksexamples/fromrecomposetohooksexample"
      component={FromRecomposeToHooksExample}
    />
    <Route path="hooksexamples/fromclasstohooksexample" component={FromClassToHooksExample} />
    <Route
      path="sharedstateexamples/liftupstatewithhooksexample"
      component={LiftUpStateWithHooksParent}
    />
    <Route
      path="sharedstateexamples/statecontextwithhooksexample"
      component={StateContextWithHooksParent}
    />
    <Route
      path="sharedstateexamples/statecontextwithhooksstatunitexample"
      component={StateContextWithHooksStatUnitParent}
    />
    <Route
      path="sharedstateexamples/liftupstatewithhooksstatunitexample"
      component={LiftUpStateWithHooksStatUnitParent}
    />
    <Route
      path="sharedstateexamples/liftupstatewithclassexample"
      component={LiftUpStateWithClassExample}
    />
    <Route path="reportsTree" component={ReportsTree} />
    <Route path="*" component={NotFound} />
  </Route>
)
