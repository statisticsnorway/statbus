import React from 'react'
import { Form } from 'semantic-ui-react'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import DatePicker from './DatePicker'

const EditLocalUnit = ({ statUnit, handleEdit, handleDateEdit,
  localize, legalUnitOptions, enterpriseUnitOptions, handleSelectEdit }) => (
    <div>
      {check('legalUnitId') &&
      <Form.Select
        name="legalUnitId"
        label={localize('LegalUnitId')}
        options={legalUnitOptions}
        value={statUnit.legalUnitId}
        onChange={handleSelectEdit}
      />
  }
      {check('enterpriseUnitRegId') &&
      <Form.Select
        name="enterpriseUnitRegId"
        label={localize('EnterpriseUnit')}
        options={enterpriseUnitOptions}
        value={statUnit.enterpriseUnitRegId}
        onChange={handleSelectEdit}
      />
  }
      {check('legalUnitIdDate') &&
      <DatePicker
        name="legalUnitIdDate"
        value={statUnit.legalUnitIdDate}
        label={localize('LegalUnitIdDate')}
        handleDateEdit={handleDateEdit('legalUnitIdDate')}
      />}
    </div>
)

const { func } = React.PropTypes

EditLocalUnit.propTypes = {
  handleEdit: func.isRequired,
}

EditLocalUnit.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(EditLocalUnit)
