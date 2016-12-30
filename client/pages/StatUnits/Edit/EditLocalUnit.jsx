import React from 'react'
import { Form } from 'semantic-ui-react'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import DatePicker from './DatePicker'

const EditLocalUnit = ({ statUnit, handleEdit, handleDateEdit }) => (<div>
  {check('legalUnitId') && <Form.Input
    value={statUnit.legalUnitId}
    onChange={handleEdit('legalUnitId')}
    name="legalUnitId"
    label="LegalUnitId"
  />}
  {check('legalUnitIdDate') &&
  <DatePicker
    {...{
      value: statUnit.legalUnitIdDate,
      label: 'LegalUnitIdDate',
      handleDateEdit: handleDateEdit('legalUnitIdDate'),
    }}
  />}
</div>)

const { func } = React.PropTypes

EditLocalUnit.propTypes = {
  handleEdit: func.isRequired,
}

export default EditLocalUnit
