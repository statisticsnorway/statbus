import React from 'react'
import { Route, IndexRoute } from 'react-router'

import { checkSystemFunction as sF } from 'helpers/config'
import Layout, { linksView, linksCreate, linksDelete } from './Layout'
import CreateLinks from './Create'
import DeleteLinks from './Delete'
import ViewLinks from './View'

export default (
  <Route path={linksView} component={Layout}>
    {sF('LinksView') && <IndexRoute component={ViewLinks} />}
    {sF('LinksCreate') && <Route path={linksCreate} component={CreateLinks} />}
    {sF('LinksDelete') && <Route path={linksDelete} component={DeleteLinks} />}
  </Route>
)
