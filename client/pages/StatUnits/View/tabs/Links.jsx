import React from 'react'
import { func, shape, oneOfType, number, string } from 'prop-types'

import Tree from '../../Links/components/LinksTree'

const Links = ({ filter, fetchData, localize }) => (
  <Tree
    filter={filter}
    getUnitsTree={fetchData}
    localize={localize}
  />
)

Links.propTypes = {
  filter: shape({
    id: oneOfType([number, string]).isRequired,
    type: oneOfType([number, string]).isRequired,
  }).isRequired,
  fetchData: func.isRequired,
  localize: func.isRequired,
}

export default Links
