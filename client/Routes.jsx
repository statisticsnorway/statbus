import React from 'react'
import { IndexRoute, Route } from 'react-router'

import { systemFunction as sF } from 'helpers/checkPermissions'
import Layout from './layout'
import Home from './pages/Home'
import AccountRoutes from './pages/Account'
import RolesRoutes from './pages/Roles'
import UsersRoutes from './pages/Users'
import About from './pages/About'
import NotFound from './pages/NotFound'
import StatUnits from './pages/StatUnits'
import AddressRoutes from './pages/Address'
import RegionsRoutes from './pages/Regions'
import DataSourcesRoutes from './pages/DataSources/Routes'
import DataSourcesQueueRoutes from './pages/DataSourcesQueue/Routes'
import LogicalChecksRoutes from './pages/LogicalChecks/Routes'

export default (
  <Route path="/" component={Layout}>
    <IndexRoute component={Home} />
    {sF('AccountView') && AccountRoutes}
    {sF('RoleView') && RolesRoutes}
    {sF('UserView') && UsersRoutes}
    {sF('StatUnitView') && StatUnits}
    {sF('AddressView') && AddressRoutes}
    {sF('RegionsView') && RegionsRoutes}
    {sF('DataSourcesView') && DataSourcesRoutes}
    {sF('DataSourcesQueueView') && DataSourcesQueueRoutes}
    {sF('StatUnitView') && LogicalChecksRoutes}
    <Route path="about" component={About} />
    <Route path="*" component={NotFound} />
  </Route>
)
