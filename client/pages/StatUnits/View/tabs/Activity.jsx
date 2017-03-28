import React from 'react'
import ActivitiesGrid from 'components/fields/Activities'

const Activity = ({ data }) => (
  <ActivitiesGrid
    name="activities"
    data={data.activities}
    readOnly
  />
)

Activity.propTypes = {
  data: React.PropTypes.object.isRequired,
}

export default Activity
