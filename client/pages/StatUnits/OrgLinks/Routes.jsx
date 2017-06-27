import React from 'react'
import { Route, IndexRoute } from 'react-router'

import { systemFunction as sF } from 'helpers/checkPermissions'
import Layout, { OrgLinksView } from './Layout'

import ViewOrgLinks from  './View'

export default (
  <Route path={OrgLinksView} component={Layout}>
    {sF('OrgLinksView') && <IndexRoute component={ViewOrgLinks} />}
  </Route>
)
