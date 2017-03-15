import React from 'react'
import { Dropdown } from 'semantic-ui-react'
import { IndexLink, Link } from 'react-router'

import { systemFunction as sF } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import SelectLocale from './SelectLocale'
import styles from './styles'

// eslint-disable-next-line no-underscore-dangle
const userName = window.__initialStateFromServer.userName || '(name not found)'

const Header = ({ localize }) => (
  <header>
    <div className={`ui inverted menu ${styles['header-menu-root']}`}>
      <div className="ui right aligned container">
        <IndexLink to="/" className={`item ${styles['header-index-link']}`}>
          <img className="logo" alt="logo" src="logo.png" width="25" height="35" />
          <text>{localize('NSCRegistry')}</text>
        </IndexLink>
        {sF('UserListView') && <Link to="/users" className="item">{localize('Users')}</Link>}
        {sF('RoleListView') && <Link to="/roles" className="item">{localize('Roles')}</Link>}
        {sF('StatUnitListView') && <Link to="/statunits" className="item">{localize('StatUnits')}</Link>}
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
