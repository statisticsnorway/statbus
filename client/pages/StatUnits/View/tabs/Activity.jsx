import React from 'react'
import { shape, func, arrayOf } from 'prop-types'

import { ActivitiesField } from 'components/fields'

const Activity = ({ data, localize }) => (
  <ActivitiesField name="activities" value={data} localize={localize} readOnly />
)

Activity.propTypes = {
  data: arrayOf(shape({})),
  localize: func.isRequired,
}

Activity.defaultProps = {
  data: undefined,
}

export default Activity
