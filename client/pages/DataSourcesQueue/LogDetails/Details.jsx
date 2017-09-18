import React from 'react'
import PropTypes from 'prop-types'
import { Segment } from 'semantic-ui-react'

import Info from 'components/Info'
// import StatUnitForm from 'components/StatUnitForm'
import { formatDateTime } from 'helpers/dateHelper'

const Details = ({ formData, errors, submitData, localize }) => (
  <Segment>
    <Info label={localize('Id')} text={formData.id} />
    <Info label={localize('Started')} text={formatDateTime(formData.started)} />
    <Info label={localize('Ended')} text={formatDateTime(formData.ended)} />
    <Info label={localize('StatId')} text={formData.statId} />
    <Info label={localize('Name')} text={formData.name} />
    <Info label={localize('Status')} text={formData.status} />
    <Info label={localize('Note')} text={formData.note} />
    {/* <StatUnitForm
      values={formData.statUnit}
      errors={errors}
      onSubmit={() => submitData(formData)}
      localize={localize}
    /> */}
  </Segment>
)

const { func, shape } = PropTypes
Details.propTypes = {
  formData: shape({}).isRequired,
  errors: shape({}).isRequired,
  submitData: func.isRequired,
  localize: func.isRequired,
}

export default Details
