import React from 'react'
import PropTypes from 'prop-types'
import { Icon } from 'semantic-ui-react'

import styles from './styles.scss'

const InsertButton = ({ onClick, title }) => (
  <Icon.Group onClick={onClick} className="cursor-pointer" title={title} size="large">
    <Icon name="add" color="blue" />
    <Icon name="external" className={styles.flipped} corner />
  </Icon.Group>
)

InsertButton.propTypes = {
  onClick: PropTypes.func.isRequired,
  title: PropTypes.string.isRequired,
}

export default InsertButton
