import React from 'react'
import PropTypes from 'prop-types'
import ActivitiesGrid from 'components/StatUnitForm/fields/Activities'

const Activity = ({ data }) => (
  <ActivitiesGrid
    name="activities"
    data={data.activities}
    readOnly
  />
)

Activity.propTypes = {
  data: PropTypes.object.isRequired,
}

export default Activity
