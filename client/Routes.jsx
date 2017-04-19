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
import RegionsRoutes from './pages/Regions'
import AddressRoutes from './pages/Address'
import DataSourcesRoutes from './pages/DataSources/Routes'

export default (
  <Route path="/" component={Layout}>
    <IndexRoute component={Home} />
    {sF('AccountView') && AccountRoutes}
    {sF('RoleView') && RolesRoutes}
    {sF('UserView') && UsersRoutes}
    {sF('StatUnitView') && StatUnits}
    {sF('RegionsView') && RegionsRoutes}
    {sF('AddressView') && AddressRoutes}
    {sF('DataSourcesView') && DataSourcesRoutes}
    <Route path="about" component={About} />
    <Route path="*" component={NotFound} />
  </Route>
)
