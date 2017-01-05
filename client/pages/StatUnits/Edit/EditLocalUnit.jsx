import React from 'react'
import { Form } from 'semantic-ui-react'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import DatePicker from './DatePicker'

const EditLocalUnit = ({ statUnit, handleEdit, handleDateEdit, localize }) => (<div>
  {check('legalUnitId') && <Form.Input
    value={statUnit.legalUnitId}
    onChange={handleEdit('legalUnitId')}
    name="legalUnitId"
    label={localize('LegalUnitId')}
  />}
  {check('legalUnitIdDate') &&
  <DatePicker
    value={statUnit.legalUnitIdDate}
    label={localize('LegalUnitIdDate')}
    handleDateEdit={handleDateEdit('legalUnitIdDate')}
  />}
</div>)

const { func } = React.PropTypes

EditLocalUnit.propTypes = {
  handleEdit: func.isRequired,
}

EditLocalUnit.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(EditLocalUnit)
