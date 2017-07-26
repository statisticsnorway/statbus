import React from 'react'
import { Route, IndexRoute } from 'react-router'
import { node } from 'prop-types'

import List from './List'
import Create from './Create'
import Edit from './Edit'
import Upload from './Upload'

const Layout = props => <div>{props.children}</div>
Layout.propTypes = { children: node.isRequired }

export default (
  <Route path="datasources" component={Layout}>
    <IndexRoute component={List} />
    <Route path="create" component={Create} />
    <Route path="edit/:id" component={Edit} />
    <Route path="upload" component={Upload} />
  </Route>
)
