import React from 'react'
import { Form } from 'semantic-ui-react'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import DatePicker from './DatePicker'

const EditEnterpriseUnit = ({ statUnit, handleEdit, handleDateEdit, localize, enterpriseGroupOptions, handleSelectEdit }) => (
  <div>
    {check('entGroupId') &&
    <Form.Select
      name="entGroupId"
      label={localize('EnterpriseGroup')}
      options={enterpriseGroupOptions}
      value={statUnit.entGroupId}
      onChange={handleSelectEdit}
    />
    }
    {check('entGroupIdDate') &&
    <DatePicker
      name="entGroupIdDate"
      value={statUnit.entGroupIdDate}
      label={localize('EntGroupIdDate')}
      handleDateEdit={handleDateEdit('entGroupIdDate')}
    />}
    {check('commercial') && <Form.Input
      value={statUnit.commercial}
      onChange={handleEdit('commercial')}
      name="commercial"
      label={localize('Commercial')}
    />}
    {check('instSectorCode') && <Form.Input
      value={statUnit.instSectorCode}
      onChange={handleEdit('instSectorCode')}
      name="instSectorCode"
      label={localize('InstSectorCode')}
    />}
    {check('totalCapital') && <Form.Input
      value={statUnit.totalCapital}
      onChange={handleEdit('totalCapital')}
      name="totalCapital"
      label={localize('TotalCapital')}
    />}
    {check('munCapitalShare') && <Form.Input
      value={statUnit.munCapitalShare}
      onChange={handleEdit('munCapitalShare')}
      name="munCapitalShare"
      label={localize('MunCapitalShare')}
    />}
    {check('stateCapitalShare') && <Form.Input
      value={statUnit.stateCapitalShare}
      onChange={handleEdit('stateCapitalShare')}
      name="stateCapitalShare"
      label={localize('StateCapitalShare')}
    />}
    {check('privCapitalShare') && <Form.Input
      value={statUnit.privCapitalShare}
      onChange={handleEdit('privCapitalShare')}
      name="privCapitalShare"
      label={localize('PrivCapitalShare')}
    />}
    {check('foreignCapitalShare') && <Form.Input
      value={statUnit.foreignCapitalShare}
      onChange={handleEdit('foreignCapitalShare')}
      name="foreignCapitalShare"
      label={localize('ForeignCapitalShare')}
    />}
    {check('foreignCapitalCurrency') && <Form.Input
      value={statUnit.foreignCapitalCurrency}
      onChange={handleEdit('foreignCapitalCurrency')}
      name="foreignCapitalCurrency"
      label={localize('ForeignCapitalCurrency')}
    />}
    {check('actualMainActivity1') && <Form.Input
      value={statUnit.actualMainActivity1}
      onChange={handleEdit('actualMainActivity1')}
      name="actualMainActivity1"
      label={localize('ActualMainActivity1')}
    />}
    {check('actualMainActivity2') && <Form.Input
      value={statUnit.actualMainActivity2}
      onChange={handleEdit('actualMainActivity2')}
      name="actualMainActivity2"
      label={localize('ActualMainActivity2')}
    />}
    {check('actualMainActivityDate') &&
    <DatePicker
      name="actualMainActivityDate"
      value={statUnit.actualMainActivityDate}
      label={localize('ActualMainActivityDate')}
      handleDateEdit={handleDateEdit('actualMainActivityDate')}
    />}
    {check('entGroupRole') && <Form.Input
      value={statUnit.entGroupRole}
      onChange={handleEdit('entGroupRole')}
      name="entGroupRole"
      label={localize('EntGroupRole')}
    />}
  </div>)

EditEnterpriseUnit.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(EditEnterpriseUnit)
