import React from 'react'


import { wrapper } from 'helpers/locale'
import ViewFilter from './ViewFilter'
import ViewTree from './ViewTree'

const { func, array, object } = React.PropTypes

class ViewLinks extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    findUnit: func.isRequired,
    units: array.isRequired,
    filter: object.isRequired,
    getUnitChildren: func.isRequired,
  }

  componentDidMount() {
    const { findUnit, filter } = this.props
    if (filter) findUnit(filter)
  }

  render() {
    const { localize, findUnit, units, filter, getUnitChildren } = this.props
    return (
      <div>
        <ViewFilter
          value={filter}
          localize={localize}
          onFilter={findUnit}
        />
        <br />
        <ViewTree
          value={units}
          localize={localize}
          loadData={getUnitChildren}
        />
      </div>
    )
  }
}

export default wrapper(ViewLinks)
