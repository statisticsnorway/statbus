import React from 'react'
import { Route, IndexRoute } from 'react-router'

import { systemFunction as sF } from 'helpers/checkPermissions'
import Layout, { linksView, linksCreate, linksDelete } from './Layout'
import CreateLinks from './Create'
import DeleteLinks from './Delete'

export default (
  <Route path={linksView} component={Layout}>
    {sF('LinksView') && <IndexRoute component={() => <div />} />}
    {sF('LinksCreate') && <Route path={linksCreate} component={CreateLinks} />}
    {sF('LinksDelete') && <Route path={linksDelete} component={DeleteLinks} />}
  </Route>
)
