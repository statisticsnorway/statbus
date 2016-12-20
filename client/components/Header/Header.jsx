import React from 'react'
import { Dropdown } from 'semantic-ui-react'
import { IndexLink, Link } from 'react-router'

import { systemFunction as sF } from 'helpers/checkPermissions'
import { getText, wrapper } from 'helpers/locale'
import SelectLocale from '../SelectLocale'
import styles from './styles'

// eslint-disable-next-line no-underscore-dangle
const userName = window.__initialStateFromServer.userName || '(name not found)'

const Header = ({ locale }) => (
  <header className={styles.root}>
    <div className={`ui inverted menu ${styles['menu-root']}`}>
      <div className="ui right aligned container">
        <IndexLink to="/" className={`item ${styles['index-link']}`}>
          <img className="logo" alt="logo" src="logo.png" width="25" height="35" />
          <text>NSC Registry</text>
        </IndexLink>
        {sF('UserListView') && <Link to="/users" className="item">{getText(locale, 'Users')}</Link>}
        {sF('RoleListView') && <Link to="/roles" className="item">{getText(locale, 'Roles')}</Link>}
        {sF('StatUnitListView') && <Link to="/statunits" className="item">{getText(locale, 'StatUnits')}</Link>}
        <div className="right menu">
          <SelectLocale />
          <Dropdown simple text={userName} className="item" icon="caret down">
            <Dropdown.Menu>
              {sF('AccountView') && <Dropdown.Item
                as={() => <Link to="/account" className="item">{getText(locale, 'Account')}</Link>}
              />}
              <Dropdown.Item
                as={() => <a href="/account/logout" className="item">{getText(locale, 'Logout')}</a>}
              />
            </Dropdown.Menu>
          </Dropdown>
        </div>
      </div>
    </div>
  </header>
)

Header.propTypes = { locale: React.PropTypes.string.isRequired }

export default wrapper(Header)
