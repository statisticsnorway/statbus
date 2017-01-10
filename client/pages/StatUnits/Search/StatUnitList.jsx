import React from 'react'
import { Item } from 'semantic-ui-react'

import ListItem from './ListItem'
import styles from './styles'

const { arrayOf, func, number, shape, string } = React.PropTypes

class StatUnitList extends React.Component {
  static propTypes = {
    statUnits: arrayOf(shape({
      regId: number.isRequired,
      name: string.isRequired,
    })).isRequired,
    deleteStatUnit: func.isRequired,
  }

  name = 'StatUnitList'

  render() {
    const { statUnits, deleteStatUnit } = this.props
    return (
      <Item.Group divided className={styles['items']}>
        {statUnits && statUnits.map(u =>
          <ListItem key={u.regId} {...u} deleteStatUnit={deleteStatUnit} />)}
      </Item.Group>
    )
  }
}

export default StatUnitList
