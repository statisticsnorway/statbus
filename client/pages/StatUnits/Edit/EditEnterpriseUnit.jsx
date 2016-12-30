import React from 'react'
import { Form } from 'semantic-ui-react'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import DatePicker from './DatePicker'

const EditEnterpriseUnit = ({ statUnit, handleEdit, handleDateEdit }) => (
  <div>
    {check('entGroupId') && <Form.Input
      value={statUnit.entGroupId}
      onChange={handleEdit('entGroupId')}
      name="entGroupId"
      label="EntGroupId"
    />}
    {check('entGroupIdDate') &&
    <DatePicker
      {...{
        value: statUnit.entGroupIdDate,
        label: 'EntGroupIdDate',
        handleDateEdit:
        handleDateEdit('entGroupIdDate'),
      }}
    />}
    {check('commercial') && <Form.Input
      value={statUnit.commercial}
      onChange={handleEdit('commercial')}
      name="commercial"
      label="Commercial"
    />}
    {check('instSectorCode') && <Form.Input
      value={statUnit.instSectorCode}
      onChange={handleEdit('instSectorCode')}
      name="instSectorCode"
      label="InstSectorCode"
    />}
    {check('totalCapital') && <Form.Input
      value={statUnit.totalCapital}
      onChange={handleEdit('totalCapital')}
      name="totalCapital"
      label="TotalCapital"
    />}
    {check('munCapitalShare') && <Form.Input
      value={statUnit.munCapitalShare}
      onChange={handleEdit('munCapitalShare')}
      name="munCapitalShare"
      label="MunCapitalShare"
    />}
    {check('stateCapitalShare') && <Form.Input
      value={statUnit.stateCapitalShare}
      onChange={handleEdit('stateCapitalShare')}
      name="stateCapitalShare"
      label="StateCapitalShare"
    />}
    {check('privCapitalShare') && <Form.Input
      value={statUnit.privCapitalShare}
      onChange={handleEdit('privCapitalShare')}
      name="privCapitalShare"
      label="PrivCapitalShare"
    />}
    {check('foreignCapitalShare') && <Form.Input
      value={statUnit.foreignCapitalShare}
      onChange={handleEdit('foreignCapitalShare')}
      name="foreignCapitalShare"
      label="ForeignCapitalShare"
    />}
    {check('foreignCapitalCurrency') && <Form.Input
      value={statUnit.foreignCapitalCurrency}
      onChange={handleEdit('foreignCapitalCurrency')}
      name="foreignCapitalCurrency"
      label="ForeignCapitalCurrency"
    />}
    {check('actualMainActivity1') && <Form.Input
      value={statUnit.actualMainActivity1}
      onChange={handleEdit('actualMainActivity1')}
      name="actualMainActivity1"
      label="ActualMainActivity1"
    />}
    {check('actualMainActivity2') && <Form.Input
      value={statUnit.actualMainActivity2}
      onChange={handleEdit('actualMainActivity2')}
      name="actualMainActivity2"
      label="ActualMainActivity2"
    />}
    {check('actualMainActivityDate') &&
    <DatePicker
      {...{
        value: statUnit.actualMainActivityDate,
        label: 'ActualMainActivityDate',
        handleDateEdit: handleDateEdit('actualMainActivityDate'),
      }}
    />}
    {check('entGroupRole') && <Form.Input
      value={statUnit.entGroupRole}
      onChange={handleEdit('entGroupRole')}
      name="entGroupRole"
      label="entGroupRole"
    />}
  </div>)

export default EditEnterpriseUnit

