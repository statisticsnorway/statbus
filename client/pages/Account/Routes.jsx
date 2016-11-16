import React from 'react'
import { Route, IndexRoute } from 'react-router'

import Edit from './Edit'

const Layout = props => <div>{props.children}</div>

export default (
  <Route path="account" component={Layout}>
    <IndexRoute component={Edit} />
  </Route>
)
