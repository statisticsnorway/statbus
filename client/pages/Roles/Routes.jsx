import React from 'react'
import { Route, IndexRoute } from 'react-router'
import { node } from 'prop-types'

import { checkSystemFunction as sF } from 'helpers/config'
import List from './List'
import Create from './Create'
import Edit from './Edit'

const Layout = props => <div>{props.children}</div>
Layout.propTypes = { children: node.isRequired }

export default (
  <Route path="roles" component={Layout}>
    <IndexRoute component={List} />
    {sF('RoleCreate') && <Route path="create" component={Create} />}
    {sF('RoleEdit') && <Route path="edit/:id" component={Edit} />}
  </Route>
)
