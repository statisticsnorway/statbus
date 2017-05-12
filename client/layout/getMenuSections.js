import React from 'react'
import { systemFunction as sF } from 'helpers/checkPermissions'
import R from 'ramda'

import MenuLink from './MenuLink'

const reducer = localize =>
  (acc, { textKey, ...rest }) =>
    sF(rest.sf)
      // eslint-disable-next-line react/jsx-filename-extension
      ? [...acc, <MenuLink {...rest} key={textKey} text={localize(textKey)} />]
      : acc

const data = {
  administration: [
    { sf: 'UserView', route: '/users', icon: 'users', textKey: 'Users' },
    { sf: 'RoleView', route: '/roles', icon: 'setting', textKey: 'Roles' },
    { sf: 'RegionsView', route: '/regions', icon: 'globe', textKey: 'Regions' },
    //{ sf: 'AddressView', route: '/addresses', icon: 'marker', textKey: 'Addresses' },
  ],
  statUnits: [
    { sf: 'StatUnitView', route: '/statunits', icon: 'search', textKey: 'StatUnitSearch' },
    { sf: 'StatUnitDelete', route: '/statunits/deleted', icon: 'undo', textKey: 'StatUnitUndelete' },
    { sf: 'StatUnitCreate', route: '/statunits/create', icon: 'add', textKey: 'StatUnitCreate' },
    { sf: 'SoateView', route: '/soates', icon: 'marker', textKey: 'Soates' },
    { sf: 'LinksView', route: '/statunits/links', icon: 'linkify', textKey: 'LinkUnits' },
  ],
  dataSources: [
    { sf: 'DataSourcesView', route: '/datasources', icon: 'file text outline', textKey: 'DataSources' },
    { sf: 'DataSourcesCreate', route: '/datasources/create', icon: 'add', textKey: 'DataSourcesCreate' },
    { sf: 'DataSourcesUpload', route: '/datasources/upload', icon: 'upload', textKey: 'DataSourcesUpload' },
    { sf: 'DataSourceQueuesView', route: '/datasourcequeues', icon: 'database', textKey: 'DataSourceQueues' },
  ],
}

export default localize => R.map(R.reduce(reducer(localize), []))(data)
