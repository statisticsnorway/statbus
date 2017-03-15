import React from 'react'
import { Dropdown } from 'semantic-ui-react'
import { IndexLink, Link } from 'react-router'

import { systemFunction as sF } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import SelectLocale from '../SelectLocale'
import MenuItem from './MenuItem'
import styles from './styles'

// eslint-disable-next-line no-underscore-dangle
const userName = window.__initialStateFromServer.userName || '(name not found)'

const administrativeTools = [
  { sf: 'UserView', route: '/users', icon: 'users', title: 'Users' },
  { sf: 'RoleView', route: '/roles', icon: 'setting', title: 'Roles' },
  { sf: 'RegionsView', route: '/regions', icon: 'globe', title: 'Regions' },
]

const tools = administrativeTools.filter(v => sF(v.sf))
const Header = ({ localize }) => (
  <header>
    <div className={`ui inverted menu ${styles['menu-root']}`}>
      <div className="ui right aligned container">
        <IndexLink to="/" className={`item ${styles['index-link']}`}>
          <img className="logo" alt="logo" src="logo.png" width="25" height="35" />
          <text>{localize('NSCRegistry')}</text>
        </IndexLink>
   
        {sF('StatUnitView') && <Link to="/statunits" className="item">{localize('StatUnits')}</Link>}
        {tools.length &&
          <Dropdown simple text={localize('AdministrativeTools')} className="item" icon="caret down">
            <Dropdown.Menu>
              {tools.map(tool => <MenuItem key={tool.title} {...{ ...tool, localize }} />)}
            </Dropdown.Menu>
          </Dropdown>
        }
        <div className="right menu">
          <SelectLocale />
          <Dropdown simple text={userName} className="item" icon="caret down">
            <Dropdown.Menu>
              {sF('AccountView') && <Dropdown.Item
                as={() => <Link to="/account" className="item">{localize('Account')}</Link>}
              />}
              <Dropdown.Item
                as={() => <a href="/account/logout" className="item">{localize('Logout')}</a>}
              />
            </Dropdown.Menu>
          </Dropdown>
        </div>
      </div>
    </div>
  </header>
  )
Header.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(Header)
