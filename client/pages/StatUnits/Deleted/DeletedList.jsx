import React from 'react'
import { Item } from 'semantic-ui-react'

import ListItem from './ListItem'
import styles from './styles'

class List extends React.Component {
  componentDidMount() {
    this.props.fetchData()
  }

  render() {
    return (
      <Item.Group divided className={styles.items}>
        {this.props.isLoading
          ? 'loading...'
          : this.props.statUnits.map(x =>
            <ListItem key={x.regId} statUnit={x} restore={this.props.restore} />)}
      </Item.Group>
    )
  }
}

const { func, arrayOf, shape, bool, string, number } = React.PropTypes

List.propTypes = {
  fetchData: func.isRequired,
  isLoading: bool.isRequired,
  restore: func.isRequired,
  statUnits: arrayOf(shape({
    regId: number.isRequired,
    name: string.isRequired,
  })).isRequired,
}

export default List
