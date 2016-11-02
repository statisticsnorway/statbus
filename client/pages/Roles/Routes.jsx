import React from 'react'
import { Route, IndexRoute, Link } from 'react-router'

import List from './List'
import Create from './Create'
import Edit from './Edit'

const Layout = props => <div>{props.children}</div>

export default (
  <Route path="roles" component={Layout}>
    <IndexRoute component={List} />
    <Route path="create" component={Create} />
    <Route path="edit/:id" component={Edit} />
  </Route>
)
