import React from 'react'
import { Route, IndexRoute } from 'react-router'

import Search from './Search'
import View from './View'
import Edit from './Edit'
import Create from './Create'
import Print from './Print'

const Layout = props => <div>{props.children}</div>

export default (
  <Route path="statunits" component={Layout}>
    <IndexRoute component={Search} />
    <Route path="view/:type/:id" component={View} />
    <Route path="edit/:type/:id" component={Edit} />
    <Route path="print/:type/:id" component={Print} />
    <Route path="create" component={Create} />
  </Route>
)
