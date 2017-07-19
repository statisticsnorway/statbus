import React from 'react'
import { shape, func } from 'prop-types'

import ActivitiesGrid from 'components/StatUnitForm/fields/Activities'

const Activity = ({ data, localize }) => (
  <ActivitiesGrid
    name="activities"
    data={data.activities}
    localize={localize}
    readOnly
  />
)

Activity.propTypes = {
  data: shape({}).isRequired,
  localize: func.isRequired,
}

export default Activity
