import React from 'react'
import { shape, func } from 'prop-types'

import ActivitiesGrid from 'components/fields/ActivitiesField'

const Activity = ({ data, localize }) => (
  <ActivitiesGrid
    name="activities"
    value={data}
    localize={localize}
    readOnly
  />
)

Activity.propTypes = {
  data: shape({}).isRequired,
  localize: func.isRequired,
}

export default Activity
