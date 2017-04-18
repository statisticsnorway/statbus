import React from 'react'
import { Route, IndexRoute } from 'react-router'

import ViewDataSourceQueues from './index'

const Layout = props => <div>{props.children}</div>

export default (
  <Route path="datasourcequeues" component={Layout}>
    <IndexRoute component={ViewDataSourceQueues} />
  </Route>
)
