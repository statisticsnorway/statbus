import React from 'react'


import { wrapper } from 'helpers/locale'
import ViewFilter from './ViewFilter'
import ViewTree from './ViewTree'

const { func, array } = React.PropTypes

class ViewLinks extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    findUnit: func.isRequired,
    units: array.isRequired,
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
