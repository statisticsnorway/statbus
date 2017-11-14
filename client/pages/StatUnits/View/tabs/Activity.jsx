import React from 'react'
import { shape, func, arrayOf } from 'prop-types'

import ActivitiesGrid from 'components/fields/ActivitiesField'

const Activity = ({ data, localize }) => (
  <ActivitiesGrid name="activities" value={data} localize={localize} readOnly />
)

Activity.propTypes = {
  data: arrayOf(shape({})).isRequired,
  localize: func.isRequired,
}

export default Activity
