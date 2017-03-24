import React from 'react'
import { systemFunction as sF } from 'helpers/checkPermissions'
import R from 'ramda'

import MenuLink from './MenuLink'

const isLinkAllowed = data => sF(data.sf)
// eslint-disable-next-line react/jsx-filename-extension
const getMenuLink = props => <MenuLink {...props} />
const setKeyProp = data => ({ ...data, key: data.textKey })
const setTextProp = localize => ({ textKey, ...rest }) => ({ ...rest, text: localize(textKey) })

const data = {
  administration: [
    { sf: 'UserView', route: '/users', icon: 'users', textKey: 'Users' },
    { sf: 'RoleView', route: '/roles', icon: 'setting', textKey: 'Roles' },
    { sf: 'RegionsView', route: '/regions', icon: 'globe', textKey: 'Regions' },
  ],
  statUnits: [
    { sf: 'StatUnitView', route: '/statunits', icon: 'search', textKey: 'StatUnitSearch' },
    { sf: 'StatUnitDelete', route: '/statunits/deleted', icon: 'undo', textKey: 'StatUnitUndelete' },
    { sf: 'StatUnitCreate', route: '/statunits/create', icon: 'add', textKey: 'StatUnitCreate' },
  ],
}

export default (localize) => {
  const setLocalizedText = setTextProp(localize)
  const getComponent = R.pipe(setKeyProp, setLocalizedText, getMenuLink)
  const f = R.pipe(R.filter(isLinkAllowed), R.map(getComponent))
  return R.map(f, data)
  // const f = x => x.filter(isAllowed).map(setKey).map(setLocalizedText).map(MenuLink)
  // return map(f, data)
}
