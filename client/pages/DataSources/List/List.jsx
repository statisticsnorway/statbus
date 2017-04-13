import React from 'react'
import { arrayOf, shape, func, string, number } from 'prop-types'

import ListItem from './ListItem'

class List extends React.Component {

  static propTypes = {
    dataSources: arrayOf(shape({
      id: number.isRequired,
      name: string.isRequired,
    })),
    totalCount: number.isRequired,
    actions: shape({
      fetchData: func.isRequired,
    }).isRequired,
  }

  static defaultProps = {
    dataSources: [],
  }

  componentDidMount() {
    this.props.actions.fetchData()
  }

  render() {
    const { dataSources, totalCount } = this.props
    return (
      <div>
        <p>total: {totalCount}</p>
        {dataSources.map(ds =>
          <ListItem key={ds.id} {...ds} />)}
      </div>
    )
  }
}

export default List
