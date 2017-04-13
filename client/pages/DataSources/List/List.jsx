import React from 'react'
import { arrayOf, shape, func, string, number } from 'prop-types'

class List extends React.Component {

  static propTypes = {
    dataSources: arrayOf(shape({
      id: number.isRequired,
      name: string.isRequired,
    })),
    fetchDataSources: func.isRequired,
  }

  static defaultProps = {
    dataSources: [],
  }

  componentDidMount() {
    this.props.fetchDataSources()
  }

  render() {
    const { dataSources } = this.props
    return (
      <div>
        {dataSources.map(ds =>
          <span key={ds.id}>{ds.name}</span>)}
      </div>
    )
  }
}

export default List
