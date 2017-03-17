import React from 'react'
import { Dropdown, Icon } from 'semantic-ui-react'
import { Link } from 'react-router'

const MenuItem = ({ icon, route, title, localize }) => (
  <Dropdown.Item as={() => <Link to={route} className="item"><Icon name={icon} />{localize(title)}</Link>} />
)
const { func, string } = React.PropTypes

MenuItem.propTypes = {
  icon: string.isRequired,
  route: string.isRequired,
  title: string.isRequired,
  localize: func.isRequired,
}

export default MenuItem
