import React from 'react'
import { Form } from 'semantic-ui-react'
import DatePicker from './DatePicker'
import moment from 'moment'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'

const EditStatUnit = ({ statUnit, handleEdit, handleDateEdit }) => (<div>
  {check('statId') && <Form.Input
    value={statUnit.statId}
    onChange={handleEdit('statId')}
    name="name"
    label="StatId"
  />}
  {check('statIdDate') &&
  <DatePicker
    {...{
      value: statUnit.statIdDate,
      label: 'TaxRegId',
      handleDateEdit: handleDateEdit('statIdDate'),
    }}
  />}
  {check('taxRegId') && <Form.Input
    value={statUnit.taxRegId}
    onChange={handleEdit('TaxRegId')}
    name="name"
    label="TaxRegId"
  />}
  {check('taxRegDate') &&
  <DatePicker
    {...{
      value: statUnit.taxRegDate,
      label: 'TaxRegDate',
      handleDateEdit: handleDateEdit('taxRegDate'),
    }}
  />}
  {check('externalId') &&
  <DatePicker
    {...{
      value: statUnit.externalId,
      label: 'ExternalId',
      handleDateEdit: handleDateEdit('externalId'),
    }}
  />}
  {check('externalIdType') && <Form.Input
    value={statUnit.externalIdType}
    onChange={handleEdit('externalIdType')}
    name="name"
    label="ExternalIdType"
  />}
  {check('externalIdDate') &&
  <DatePicker
    {...{
      value: statUnit.externalIdDate,
      label: 'ExternalIdDate',
      handleDateEdit: handleDateEdit('externalIdDate'),
    }}
  />}
  {check('dataSource') && <Form.Input
    value={statUnit.dataSource}
    onChange={handleEdit('dataSource')}
    name="name"
    label="dataSource"
  />}
  {check('refNo') && <Form.Input
    value={statUnit.refNo}
    onChange={handleEdit('refNo')}
    name="name"
    label="refNo"
  />}
  {check('name') && <Form.Input
    value={statUnit.name}
    onChange={handleEdit('name')}
    name="name"
    label="Name"
  />}
  {check('shortName') && <Form.Input
    value={statUnit.shortName}
    onChange={handleEdit('shortName')}
    name="name"
    label="ShortName"
  />}
  {check('postalAddressId') && <Form.Input
    value={statUnit.postalAddressId}
    onChange={handleEdit('postalAddressId')}
    name="name"
    label="PostalAddressId"
  />}
  {check('telephoneNo') && <Form.Input
    value={statUnit.telephoneNo}
    onChange={handleEdit('telephoneNo')}
    name="name"
    label="TelephoneNo"
  />}
  {check('emailAddress') && <Form.Input
    value={statUnit.emailAddress}
    onChange={handleEdit('emailAddress')}
    name="name"
    label="EmailAddress"
  />}
  {check('webAddress') && <Form.Input
    value={statUnit.webAddress}
    onChange={handleEdit('webAddress')}
    name="name"
    label="WebAddress"
  />}
  {check('regMainActivity') && <Form.Input
    value={statUnit.regMainActivity}
    onChange={handleEdit('regMainActivity')}
    name="name"
    label="RegMainActivity"
  />}
  {check('registrationDate') &&
  <DatePicker
    {...{
      value: statUnit.registrationDate,
      label: 'RegistrationDate',
      handleDateEdit: handleDateEdit('registrationDate'),
    }}
  />}
  {check('registrationReason') && <Form.Input
    value={statUnit.registrationReason}
    onChange={handleEdit('registrationReason')}
    name="name"
    label="RegistrationReason"
  />}
  {check('liqDate') && <Form.Input
    value={statUnit.liqDate}
    onChange={handleEdit('liqDate')}
    name="name"
    label="LiqDate"
  />}
  {check('liqReason') && <Form.Input
    value={statUnit.liqReason}
    onChange={handleEdit('liqReason')}
    name="name"
    label="LiqReason"
  />}
  {check('suspensionStart') && <Form.Input
    value={statUnit.suspensionStart}
    onChange={handleEdit('suspensionStart')}
    name="name"
    label="SuspensionStart"
  />}
  {check('suspensionEnd') && <Form.Input
    value={statUnit.suspensionEnd}
    onChange={handleEdit('suspensionEnd')}
    name="name"
    label="SuspensionEnd"
  />}
  {check('reorgTypeCode') && <Form.Input
    value={statUnit.reorgTypeCode}
    onChange={handleEdit('reorgTypeCode')}
    name="name"
    label="ReorgTypeCode"
  />}
  {check('reorgDate') &&
  <DatePicker
    {...{
      value: statUnit.reorgDate,
      label: 'ReorgDate',
      handleDateEdit: handleDateEdit('reorgDate'),
    }}
  />}
  {check('reorgReferences') && <Form.Input
    value={statUnit.reorgReferences}
    onChange={handleEdit('reorgReferences')}
    name="name"
    label="ReorgReferences"
  />}
  {check('actualAddress') && <Form.Input
    value={statUnit.actualAddress}
    onChange={handleEdit('actualAddress')}
    name="name"
    label="ActualAddress"
  />}
  {check('contactPerson') && <Form.Input
    value={statUnit.contactPerson}
    onChange={handleEdit('contactPerson')}
    name="name"
    label="СontactPerson"
  />}
  {check('employees') && <Form.Input
    value={statUnit.employees}
    onChange={handleEdit('employees')}
    name="name"
    label="Employees"
  />}
  {check('numOfPeople') && <Form.Input
    value={statUnit.numOfPeople}
    onChange={handleEdit('numOfPeople')}
    name="name"
    label="NumOfPeople"
  />}
  {check('employeesYear') && <DatePicker
    {...{
      value: statUnit.employeesYear,
      label: 'EmployeesYear',
      handleDateEdit: handleDateEdit('employeesYear'),
    }}
  />}
  {check('employeesDate') && <DatePicker
    {...{
      value: statUnit.employeesDate,
      label: 'EmployeesDate',
      handleDateEdit: handleDateEdit('employeesDate'),
    }}
  />}
  {check('turnover') && <Form.Input
    value={statUnit.turnover}
    onChange={handleEdit('turnover')}
    name="name"
    label="Turnover"
  />}
  {check('turnoverYear') &&
  <DatePicker
    {...{
      value: statUnit.turnoverYear,
      label: 'TurnoverYear',
      handleDateEdit: handleDateEdit('turnoverYear'),
    }}
  />}
  {check('turnoveDate') &&
  <DatePicker
    {...{
      value: statUnit.turnoveDate,
      label: 'TurnoveDate',
      handleDateEdit: handleDateEdit('turnoveDate'),
    }}
  />}
  {check('status') && <Form.Input
    value={statUnit.status}
    onChange={handleEdit('status')}
    name="status"
    label="Status"
  />}
  {check('statusDate') && <DatePicker
    {...{
      value: statUnit.statusDate,
      label: 'StatusDate',
      handleDateEdit: handleDateEdit('statusDate'),
    }}
  />}
  {check('notes') && <Form.Input
    value={statUnit.notes}
    onChange={handleEdit('notes')}
    name="notes"
    label="Notes"
  />}
  {check('freeEconZone') && <Form.Input
    value={statUnit.freeEconZone}
    onChange={handleEdit('freeEconZone')}
    name="freeEconZone"
    label="FreeEconZone"
  />}
  {check('foreignParticipation') && <Form.Input
    value={statUnit.foreignParticipation}
    onChange={handleEdit('foreignParticipation')}
    name="foreignParticipation"
    label="ForeignParticipation"
  />}
  {check('classified') && <Form.Input
    value={statUnit.classified}
    onChange={handleEdit('classified')}
    name="classified"
    label="Classified"
  />}
  {check('isDeleted') && <Form.Input
    value={statUnit.isDeleted}
    onChange={handleEdit('isDeleted')}
    name="isDeleted"
    label="IsDeleted"
  />}
</div>)
const { func } = React.PropTypes

EditStatUnit.propTypes = {
  handleEdit: func.isRequired,
  handleDateEdit: func.isRequired,
}

export default EditStatUnit
