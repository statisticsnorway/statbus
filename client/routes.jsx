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
import StatUnitLinksRoutes from 'pages/StatUnits/Links/Routes'

import RolesRoutes from 'pages/Roles/Routes'
import UsersRoutes from 'pages/Users/Routes'
import AddressRoutes from 'pages/Address/Routes'
import RegionsRoutes from 'pages/Regions/Routes'
import DataSourcesRoutes from 'pages/DataSources/Routes'
import DataSourcesQueueRoutes from 'pages/DataSourcesQueue/Routes'
import LogicalChecksRoutes from 'pages/LogicalChecks/Routes'

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
    {sF('RoleView') && RolesRoutes}
    {sF('UserView') && UsersRoutes}
    {sF('AddressView') && AddressRoutes}
    {sF('RegionsView') && RegionsRoutes}
    {sF('DataSourcesView') && DataSourcesRoutes}
    {sF('DataSourcesQueueView') && DataSourcesQueueRoutes}
    {sF('StatUnitView') && LogicalChecksRoutes}
    <Route path="*" component={NotFound} />
  </Route>
)
