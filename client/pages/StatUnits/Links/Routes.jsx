import React from 'react'
import { Route, IndexRoute } from 'react-router'

import Layout, { linksView, linksCreate } from './Layout'
import CreateLinks from './Create'

export default (
  <Route path={linksView} component={Layout}>
    <IndexRoute component={CreateLinks} />
    <Route path={linksCreate} component={CreateLinks} />
  </Route>
)
