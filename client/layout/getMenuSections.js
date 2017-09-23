import React from 'react'
import { map, reduce } from 'ramda'

import { checkSystemFunction as sF } from 'helpers/config'
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
    // { sf: 'StatUnitView', route: '/analyzeregister',
    // icon: 'check circle outline', textKey: 'Analysis' },
    //{ sf: 'AddressView', route: '/addresses', icon: 'marker', textKey: 'Addresses' },
  ],
  statUnits: [
    { sf: 'StatUnitView', route: '/statunits', icon: 'search', textKey: 'StatUnitSearch' },
    { sf: 'StatUnitDelete', route: '/statunits/deleted', icon: 'undo', textKey: 'StatUnitUndelete' },
    { sf: 'StatUnitCreate', route: '/statunits/create/1', icon: 'add', textKey: 'StatUnitCreate' },
    { sf: 'RegionsView', route: '/regions', icon: 'marker', textKey: 'Regions' },
    { sf: 'LinksView', route: '/statunits/links', icon: 'linkify', textKey: 'LinkUnits' },
  ],
  dataSources: [
    { sf: 'DataSourcesView', route: '/datasources', icon: 'file text outline', textKey: 'DataSources' },
    { sf: 'DataSourcesCreate', route: '/datasources/create', icon: 'add', textKey: 'DataSourcesCreate' },
    { sf: 'DataSourcesQueueAdd', route: '/datasources/upload', icon: 'upload', textKey: 'DataSourcesUpload' },
    { sf: 'DataSourcesQueueView', route: '/datasourcesqueue', icon: 'database', textKey: 'DataSourceQueues' },
  ],
}

export default localize => map(reduce(reducer(localize), []))(data)
