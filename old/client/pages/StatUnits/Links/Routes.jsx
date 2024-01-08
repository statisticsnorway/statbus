import React from 'react'
import { Route, IndexRoute } from 'react-router'

import { checkSystemFunction as sF } from '/helpers/config'
import Layout, { linksView, linksCreate, linksDelete } from './Layout.jsx'
import CreateLinks from './Create/index.js'
import DeleteLinks from './Delete/index.js'
import ViewLinks from './View/index.js'

export default (
  <Route path={linksView} component={Layout}>
    {sF('LinksView') && <IndexRoute component={ViewLinks} />}
    {sF('LinksCreate') && <Route path={linksCreate} component={CreateLinks} />}
    {sF('LinksDelete') && <Route path={linksDelete} component={DeleteLinks} />}
  </Route>
)
