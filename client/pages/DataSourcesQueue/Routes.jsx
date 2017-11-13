import React from 'react'
import { Route, IndexRoute } from 'react-router'
import { node } from 'prop-types'

import List from './List'
import QueueLog from './QueueLog'
import LogDetails from './LogDetails'

const Layout = props => <div>{props.children}</div>
Layout.propTypes = { children: node.isRequired }

export default (
  <Route path="datasourcesqueue" component={Layout}>
    <IndexRoute component={List} />
    <Route path=":id/log" component={QueueLog} />
    <Route path=":queueId/log/:logId" component={LogDetails} />
  </Route>
)
