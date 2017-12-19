import React from 'react'
import { Route, IndexRoute } from 'react-router'
import { node } from 'prop-types'

import Queue from './Queue'
import Create from './Create'
import Logs from './Logs'

const Layout = props => <div>{props.children}</div>
Layout.propTypes = { children: node.isRequired }

export default (
  <Route path="analysisqueue" component={Layout}>
    <IndexRoute component={Queue} />
    <Route path="create" component={Create} />
    <Route path=":queueId" component={Logs} />
  </Route>
)
