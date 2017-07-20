import React from 'react'
import { func, shape, oneOfType, number, string } from 'prop-types'
import { Link } from 'react-router'
import { Button, Segment } from 'semantic-ui-react'

import { systemFunction as sF } from 'helpers/checkPermissions'
import LinksTree from '../../Links/components/LinksTree'

const Links = ({ filter, fetchData, localize }) => (
  <div>
    <Segment>
      <LinksTree
        filter={filter}
        getUnitsTree={fetchData}
        localize={localize}
      />
    </Segment>
    {sF('LinksCreate') && <Button
      as={Link}
      to={`/statunits/links/create?id=${filter.id}&type=${filter.type}`}
      content={localize('LinksViewAddLinkBtn')}
      positive
    />}
  </div>
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
