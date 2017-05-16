import React from 'react'
import { Route, IndexRoute } from 'react-router'
import { node } from 'prop-types'

import List from './List'

const Layout = props => <div>{props.children}</div>
Layout.propTypes = { children: node.isRequired }

export default (
  <Route path="analyzeregister" component={Layout}>
    <IndexRoute component={List} />
  </Route>
)
