import React from 'react'
import { Form } from 'semantic-ui-react'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import DatePicker from './DatePicker'

const EditLocalUnit = ({ statUnit, handleEdit, handleDateEdit }) => (<div>
  {check('enterpriseRegId') && <Form.Input
    value={statUnit.enterpriseRegId}
    onChange={handleEdit('enterpriseRegId')}
    name="enterpriseRegId"
    label="EnterpriseRegId"
  />}
  {check('entRegIdDate') &&
  <DatePicker
    {...{
      value: statUnit.entRegIdDate,
      label: 'EntRegIdDate',
      handleDateEdit: handleDateEdit('entRegIdDate'),
    }}
  />}
  {check('founders') && <Form.Input
    value={statUnit.founders}
    onChange={handleEdit('founders')}
    name="founders"
    label="Founders"
  />}
  {check('owner') && <Form.Input
    value={statUnit.owner}
    onChange={handleEdit('owner')}
    name="owner"
    label="Owner"
  />}
  {check('market') && <Form.Input
    value={statUnit.market}
    onChange={handleEdit('market')}
    name="market"
    label="Market"
  />}
  {check('legalForm') && <Form.Input
    value={statUnit.legalForm}
    onChange={handleEdit('legalForm')}
    name="legalForm"
    label="LegalForm"
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
</div>)

const { func } = React.PropTypes

EditLocalUnit.propTypes = {
  handleEdit: func.isRequired,
}

export default EditLocalUnit
