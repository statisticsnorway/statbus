import React from 'react'
import { func, string } from 'prop-types'
import { Label } from 'semantic-ui-react'

import styles from './styles.pcss'

const MappingItem = ({ attribute, column, onClick, color }) => (
  // eslint-disable-next-line jsx-a11y/no-static-element-interactions, jsx-a11y/click-events-have-key-events
  <div onClick={onClick} title="remove" className={styles['mappings-item']}>
    <Label content={attribute} pointing="right" color={color} basic />
    <Label content={column} pointing="left" color={color} basic />
  </div>
)

MappingItem.propTypes = {
  attribute: string.isRequired,
  column: string.isRequired,
  onClick: func.isRequired,
  color: string.isRequired,
}

export default MappingItem
