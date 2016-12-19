import React from 'react'
import { List } from 'semantic-ui-react'

import ListItem from './ListItem'

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
      <List>
        {statUnits && statUnits.map(u =>
          <ListItem key={u.regId} {...u} deleteStatUnit={deleteStatUnit} />)}
      </List>
    )
  }
}

export default StatUnitList
