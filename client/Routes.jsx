import React from 'react'
import { IndexRoute, Route } from 'react-router'

import Layout from './layout'
import Home from './pages/Home'
import AccountRoutes from './pages/Account'
import RolesRoutes from './pages/Roles'
import UsersRoutes from './pages/Users'
import About from './pages/About'
import NotFound from './pages/NotFound'

export default (
  <Route path="/" component={Layout}>
    <IndexRoute component={Home} />
    {AccountRoutes}
    {RolesRoutes}
    {UsersRoutes}
    <Route path="about" component={About} />
    <Route path="*" component={NotFound} />
  </Route>
)
