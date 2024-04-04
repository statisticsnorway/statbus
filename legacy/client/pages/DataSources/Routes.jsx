import React from 'react'
import { Route, IndexRoute } from 'react-router'
import { node } from 'prop-types'

import List from './List/index.js'
import Create from './Create.js'
import Edit from './Edit.js'
import Upload from './Upload/index.js'

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
