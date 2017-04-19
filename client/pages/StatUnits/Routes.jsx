import React from 'react'
import { Route, IndexRoute } from 'react-router'
import { node } from 'prop-types'

import { systemFunction as sF } from 'helpers/checkPermissions'
import Search from './Search'
import View from './View'
import Edit from './Edit'
import Create from './Create'
import DeletedList from './Deleted'
import LinksRoutes from './Links'

const Layout = props => <div>{props.children}</div>
Layout.propTypes = { children: node.isRequired }

export default (
  <Route path="statunits" component={Layout}>
    <IndexRoute component={Search} />
    <Route path="view/:type/:id" component={View} />
    {sF('StatUnitDelete') && <Route path="deleted" component={DeletedList} />}
    {sF('StatUnitEdit') && <Route path="edit/:type/:id" component={Edit} />}
    {sF('StatUnitCreate') && <Route path="create" component={Create} />}
    {LinksRoutes}
  </Route>
)
