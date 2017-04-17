import React from 'react'
import { Dropdown } from 'semantic-ui-react'
import { IndexLink, Link } from 'react-router'
import shouldUpdate from 'recompose/shouldUpdate'

import { systemFunction as sF } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import getMenuSectons from './getMenuSections'
import SelectLocale from './SelectLocale'
import styles from './styles'

// eslint-disable-next-line no-underscore-dangle
const userName = window.__initialStateFromServer.userName || '(name not found)'

const Header = ({ localize }) => {
  const { administration, statUnits } = getMenuSectons(localize)
  return (
    <header>
      <div className={`ui inverted menu ${styles['header-menu-root']}`}>
        <div className="ui right aligned container">
          <IndexLink to="/" className={`item ${styles['header-index-link']}`}>
            <img className="logo" alt="logo" src="logo.png" width="25" height="35" />
            <text>{localize('NSCRegistry')}</text>
          </IndexLink>
          {statUnits.length !== 0 &&
            <Dropdown simple text={localize('StatUnits')} className="item" icon="caret down">
              <Dropdown.Menu>
                {statUnits}
              </Dropdown.Menu>
            </Dropdown>}
          {administration.length !== 0 &&
            <Dropdown simple text={localize('AdministrativeTools')} className="item" icon="caret down">
              <Dropdown.Menu>
                {administration}
              </Dropdown.Menu>
            </Dropdown>}
          <div className="right menu">
            <SelectLocale className={styles['to-z-index']} />
            <Dropdown simple text={userName} className="item" icon="caret down">
              <Dropdown.Menu className={styles['to-z-index']}>
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
}

Header.propTypes = {
  localize: React.PropTypes.func.isRequired,
}

export const checkProps = (props, nextProps) =>
  nextProps.localize.lang !== props.localize.lang

export default wrapper(shouldUpdate(checkProps)(Header))
