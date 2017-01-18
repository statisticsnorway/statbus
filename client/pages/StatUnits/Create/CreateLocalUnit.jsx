import React from 'react'
import { Form } from 'semantic-ui-react'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import DatePicker from 'components/DatePicker'

const CreateLocalUnit = ({ statUnit, handleEdit, handleDateEdit,
  localize, legalUnitOptions, enterpriseUnitOptions, handleSelectEdit }) => (
    <div>
      {check('legalUnitId') &&
      <Form.Select
        name="legalUnitId"
        label={localize('LegalUnitId')}
        options={legalUnitOptions}
        value={statUnit.legalUnitId}
        onChange={handleSelectEdit}
        required
      />
    }
     {check('enterpriseUnitRegId') &&
      <Form.Select
        name="enterpriseUnitRegId"
        label={localize('EnterpriseUnit')}
        options={enterpriseUnitOptions}
        value={statUnit.enterpriseUnitRegId}
        onChange={handleSelectEdit}
        required
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

CreateLocalUnit.propTypes = {
  handleEdit: func.isRequired,
}

CreateLocalUnit.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(CreateLocalUnit)
