import React from 'react'

import Tree from '../../Links/Components/LinksTree'

const Links = ({ localize, getUnitLinks }) => (
  <Tree
    localize={localize}
    getUnitsTree={getUnitLinks}
  />
)

export default Links
