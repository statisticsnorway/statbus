import React from 'react'
import { Item } from 'semantic-ui-react'

import ListItem from './ListItem'
import styles from './styles'

const { arrayOf, func, number, shape, string } = React.PropTypes

const StatUnitList = ({ statUnits, deleteStatUnit }) => (
  <Item.Group divided className={styles.items}>
    {statUnits && statUnits.map(u =>
      <ListItem key={`${u.regId} ${u.type}`} {...u} deleteStatUnit={deleteStatUnit} />)}
  </Item.Group>
)

StatUnitList.propTypes = {
  statUnits: arrayOf(shape({
    regId: number.isRequired,
    name: string.isRequired,
  })).isRequired,
  deleteStatUnit: func.isRequired,
}

export default StatUnitList
