import React from 'react'
import { Form, Checkbox } from 'semantic-ui-react'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import DatePicker from 'components/DatePicker'

const CreateLegalUnit = ({ statUnit, handleEdit, handleDateEdit, localize, enterpriseUnitOptions, handleSelectEdit }) => (
  <div>
    {check('enterpriseRegId') &&
    <Form.Select
      name="enterpriseRegId"
      label={localize('EnterpriseUnit')}
      options={enterpriseUnitOptions}
      value={statUnit.enterpriseRegId}
      onChange={handleSelectEdit}
      required
    />}
    {check('entRegIdDate') &&
    <DatePicker
      name="entRegIdDate"
      value={statUnit.entRegIdDate}
      label={localize('EntRegIdDate')}
      handleDateEdit={handleDateEdit('entRegIdDate')}
    />}
    {check('founders') && <Form.Input
      value={statUnit.founders}
      onChange={handleEdit('founders')}
      name="founders"
      label={localize('Founders')}
    />}
    {check('owner') && <Form.Input
      value={statUnit.owner}
      onChange={handleEdit('owner')}
      name="owner"
      label={localize('Owner')}
    />}
    {check('market') &&
    <Checkbox
      value={statUnit.market}
      onChange={handleEdit('market')}
      name="market"
      label={localize('Market')}
    />}
    {check('legalForm') && <Form.Input
      value={statUnit.legalForm}
      onChange={handleEdit('legalForm')}
      name="legalForm"
      label={localize('LegalForm')}
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
  </div>)

const { func } = React.PropTypes

CreateLegalUnit.propTypes = {
  handleEdit: func.isRequired,
}

CreateLegalUnit.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(CreateLegalUnit)
