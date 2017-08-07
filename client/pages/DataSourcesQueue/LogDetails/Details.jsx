import React from 'react'
import PropTypes from 'prop-types'
import { Segment } from 'semantic-ui-react'

import Info from 'components/Info'
import { formatDateTime } from 'helpers/dateHelper'
import StatUnitForm from './ConnectedForm'

const Form = ({ formData, schema, errors, submitData, localize }) => (
  <Segment>
    <Info label={localize('Id')} text={formData.id} />
    <Info label={localize('Started')} text={formatDateTime(formData.started)} />
    <Info label={localize('Ended')} text={formatDateTime(formData.ended)} />
    <Info label={localize('StatId')} text={formData.statId} />
    <Info label={localize('Name')} text={formData.name} />
    <Info label={localize('Status')} text={formData.status} />
    <Info label={localize('Note')} text={formData.note} />
    <StatUnitForm
      statUnit={formData.statUnit}
      errors={errors}
      schema={schema}
      onSubmit={() => submitData(formData)}
      localize={localize}
    />
  </Segment>
)

const { func, shape } = PropTypes
Form.propTypes = {
  formData: shape({}).isRequired,
  schema: shape({}).isRequired,
  errors: shape({}).isRequired,
  submitData: func.isRequired,
  localize: func.isRequired,
}

export default Form
