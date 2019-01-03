import React from 'react'
import PropTypes from 'prop-types'
import { Dropdown, Icon, Responsive, Menu, Sidebar, Segment, Grid } from 'semantic-ui-react'
import { IndexLink, Link } from 'react-router'

import config, { checkSystemFunction as sF } from 'helpers/config'
import { withLocalize } from 'helpers/locale'
import createMenuMeta from './createMenuMeta'
import SelectLocale from './SelectLocale'
import styles from './styles.pcss'

class Header extends React.Component {
  state = {
    isOpen: false,
  }

  onToggle = () => {
    this.setState({ isOpen: !this.state.isOpen })
  }

  render() {
    const { localize } = this.props
    const { isOpen } = this.state
    return (
      <header>
        <div className={`ui inverted menu ${styles['header-menu-root']}`}>
          <div className="ui right aligned container">
            <IndexLink to="/" className={`item ${styles['header-index-link']}`}>
              <img className="logo" alt="logo" src="logo.png" width="25" height="35" />
              <span>{localize('NSCRegistry')}</span>
            </IndexLink>
            <Responsive minWidth={1200} className={styles.header_dropdowns}>
              {Object.entries(createMenuMeta(localize)).map(([section, links]) => (
                <div>
                  <Dropdown
                    key={section}
                    text={section}
                    icon="caret down"
                    className={`item ${styles['header_dropdown-item']}`}
                  >
                    <Dropdown.Menu>
                      {links.map(({ key, route, text, icon }) => (
                        <Dropdown.Item key={key} as={Link} to={route} className="item">
                          <Icon name={icon} />
                          {text}
                        </Dropdown.Item>
                      ))}
                    </Dropdown.Menu>
                  </Dropdown>
                </div>
              ))}
              {sF('Reports') && (
                <Link to="/reportsTree" className={`item ${styles['header-index-link']}`}>
                  {localize('Reports')}
                </Link>
              )}
            </Responsive>
            {isOpen && (
              <Responsive maxWidth={1200}>
                <Sidebar
                  inverted
                  as={Segment}
                  animation="overlay"
                  direction="right"
                  visible={isOpen}
                >
                  <Grid textAlign="center">
                    <Grid.Row>
                      <Grid.Column width={6} floated="right" stretched>
                        <Icon
                          name="cancel"
                          size="large"
                          onClick={this.onToggle}
                          className={styles['header_burger-menu-icon']}
                        />
                      </Grid.Column>
                      {Object.entries(createMenuMeta(localize)).map(([section, links]) => (
                        <Grid.Column width={16} key={section}>
                          <Dropdown text={section} icon="caret down" className="item">
                            <Dropdown.Menu>
                              {links.map(({ key, route, text, icon }) => (
                                <Dropdown.Item key={key} as={Link} to={route} className="item">
                                  <Icon name={icon} />
                                  {text}
                                </Dropdown.Item>
                              ))}
                            </Dropdown.Menu>
                          </Dropdown>
                        </Grid.Column>
                      ))}
                      <Grid.Column width={16}>
                        {sF('Reports') && (
                          <Link to="/reportsTree" className={`item ${styles['header-index-link']}`}>
                            {localize('Reports')}
                          </Link>
                        )}
                      </Grid.Column>
                    </Grid.Row>
                  </Grid>
                </Sidebar>
              </Responsive>
            )}
            <div className="right menu">
              <Menu.Item className={styles['header_burger-menu-icon']} onClick={this.onToggle}>
                <Responsive maxWidth={1200}>
                  <Icon name="sidebar" inverted size="large" />
                </Responsive>
              </Menu.Item>
              <SelectLocale className={styles['to-z-index']} />
              <Dropdown
                simple
                text={config.userName || localize('UserNameNotFound')}
                className="item"
                icon="caret down"
              >
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
  }
}

Header.propTypes = {
  localize: PropTypes.func.isRequired,
}

export default withLocalize(Header)
