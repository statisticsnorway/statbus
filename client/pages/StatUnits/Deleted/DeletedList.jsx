import React from 'react'
import { Item } from 'semantic-ui-react'
import R from 'ramda'

import Pagination from 'components/Pagination'
import queryObjToString from 'helpers/queryHelper'
import ListItem from './ListItem'
import styles from './styles'

class List extends React.Component {

  componentDidMount() {
    this.props.fetchData()
  }

  componentWillReceiveProps(nextProps) {
    if (R.equals(nextProps.route.query, this.props.route.query)) {
      this.props.fetchData()
    }
  }

  render() {
    const {
      state: { isLoading, statUnits },
      route: { params, query, pathname },
      restore,
    } = this.props
    return (
      <div>
        <Item.Group divided className={styles.items}>
          {isLoading
            ? 'loading...'
            : statUnits.map(x => <ListItem key={x.regId} statUnit={x} restore={restore} />)}
        </Item.Group>
        <Pagination {...{ currentPage: query.page, totalPages, queryObj, pathname }} />
      </div>
    )
  }
}

const { func, arrayOf, shape, bool, string, number } = React.PropTypes

List.propTypes = {
  fetchData: func.isRequired,
  restore: func.isRequired,
  state: shape({
    statUnits: arrayOf(shape({
      regId: number.isRequired,
      name: string.isRequired,
    })).isRequired,
    isLoading: bool.isRequired,
  }).isRequired,
  route: shape({
    params: object,
    query: object,
    pathname: string.isRequired,
  }).isRequired,
}

export default List
