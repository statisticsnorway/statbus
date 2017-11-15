import React from 'react'
import { func } from 'prop-types'
import { Dropdown, Icon } from 'semantic-ui-react'
import { IndexLink, Link } from 'react-router'

import config, { checkSystemFunction as sF } from 'helpers/config'
import { withLocalize } from 'helpers/locale'
import createMenuMeta from './createMenuMeta'
import SelectLocale from './SelectLocale'
import styles from './styles.pcss'

const userName = config.userName || '(name not found)'

const Header = ({ localize }) => (
  <header>
    <div className={`ui inverted menu ${styles['header-menu-root']}`}>
      <div className="ui right aligned container">
        <IndexLink to="/" className={`item ${styles['header-index-link']}`}>
          <img className="logo" alt="logo" src="logo.png" width="25" height="35" />
          <text>{localize('NSCRegistry')}</text>
        </IndexLink>
        {Object.entries(createMenuMeta(localize)).map(([section, links]) => (
          <Dropdown key={section} text={section} icon="caret down" className="item" simple>
            <Dropdown.Menu>
              {links.map(({ key, route, text, icon }) => (
                <Dropdown.Item key={key} as={Link} to={route} className="item">
                  <Icon name={icon} />
                  {text}
                </Dropdown.Item>
              ))}
            </Dropdown.Menu>
          </Dropdown>
        ))}
        <div className="right menu">
          <SelectLocale className={styles['to-z-index']} />
          <Dropdown simple text={userName} className="item" icon="caret down">
            <Dropdown.Menu className={styles['to-z-index']}>
              {sF('AccountView') && (
                <Dropdown.Item
                  as={Link}
                  to="/account"
                  content={localize('Account')}
                  className="item"
                />
              )}
              <Dropdown.Item
                as="a"
                href="/account/logout"
                content={localize('Logout')}
                className="item"
              />
            </Dropdown.Menu>
          </Dropdown>
        </div>
      </div>
    </div>
  </header>
)

Header.propTypes = {
  localize: func.isRequired,
}

export default withLocalize(Header)
