import React from 'react'
import { Item } from 'semantic-ui-react'

import ListItem from './ListItem'
import styles from './styles'

class List extends React.Component {

  componentDidMount() {
    this.props.fetchData()
  }

  render() {
    const { isLoading, statUnits, restore, fetchData } = this.props
    return (
      <Paginate fetchData={fetchData}>
        <Item.Group divided className={styles.items}>
          {isLoading
            ? 'loading...'
            : statUnits.map(x => <ListItem key={x.regId} statUnit={x} restore={restore} />)}
        </Item.Group>
      </Paginate>
    )
  }
}

const { func, arrayOf, shape, bool, string, number } = React.PropTypes

List.propTypes = {
  fetchData: func.isRequired,
  restore: func.isRequired,
  statUnits: arrayOf(shape({
    regId: number.isRequired,
    name: string.isRequired,
  })).isRequired,
  isLoading: bool.isRequired,
}

export default List
