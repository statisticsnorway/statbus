import React from 'react'
import { Dropdown } from 'semantic-ui-react'
import { IndexLink, Link } from 'react-router'

import styles from './styles'

// eslint-disable-next-line no-underscore-dangle
const userName = window.__initialStateFromServer.userName || '(name not found)'

export default () => (
  <header className={styles.root}>
    <div className={`ui inverted menu ${styles['menu-root']}`}>
      <div className="ui right aligned container">
        <IndexLink to="/" className={`item ${styles['index-link']}`}>
          <img className="logo" alt="logo" src="logo.png" width="25" height="35" />
          <text>NSC Registry</text>
        </IndexLink>
        <Link to="/users" className="item">Users</Link>
        <Link to="/roles" className="item">Roles</Link>
        <div className="right menu">
          <Dropdown simple text="Language" className="item" icon="caret down">
            <Dropdown.Menu>
              <Dropdown.Item>English</Dropdown.Item>
              <Dropdown.Item>Русский</Dropdown.Item>
              <Dropdown.Item>Кыргызча</Dropdown.Item>
            </Dropdown.Menu>
          </Dropdown>
          <Dropdown simple text={userName} className="item" icon="caret down">
            <Dropdown.Menu>
              <Dropdown.Item
                as={() => <Link to="/account" className="item">Account</Link>}
              />
              <Dropdown.Item
                as={() => <a href="/account/logout" className="item">Logout</a>}
              />
            </Dropdown.Menu>
          </Dropdown>
        </div>
      </div>
    </div>
  </header>
)
