import React from 'react'
import { string } from 'prop-types'
import { Dropdown, Icon } from 'semantic-ui-react'
import { Link } from 'react-router'

const MenuLink = ({ icon, route, text }) => (
  <Dropdown.Item
    as={() => (
      <Link to={route} className="item">
        <Icon name={icon} />
        {text}
      </Link>
    )}
  />
)

MenuLink.propTypes = {
  icon: string.isRequired,
  route: string.isRequired,
  text: string.isRequired,
}

export default MenuLink
