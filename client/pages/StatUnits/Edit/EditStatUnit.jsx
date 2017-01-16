import React from 'react'
import { Form } from 'semantic-ui-react'
import DatePicker from './DatePicker'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'

const EditStatUnit = ({ statUnit, handleEdit, handleDateEdit, localize }) => (<div>
  {check('statId') && <Form.Input
    value={statUnit.statId}
    onChange={handleEdit('statId')}
    name="name"
    label={localize('StatId')}
  />}
  {check('statIdDate') &&
  <DatePicker
    name="statIdDate"
    value={statUnit.statIdDate}
    label={localize('TaxRegId')}
    handleDateEdit={handleDateEdit('statIdDate')}
  />}
  {check('taxRegId') && <Form.Input
    value={statUnit.taxRegId}
    onChange={handleEdit('taxRegId')}
    name="name"
    label={localize('TaxRegId')}
  />}
  {check('taxRegDate') &&
  <DatePicker
    name="taxRegDate"
    value={statUnit.taxRegDate}
    label={localize('TaxRegDate')}
    handleDateEdit={handleDateEdit('taxRegDate')}
  />}
  {check('externalId') &&
  <DatePicker
    name="externalId"
    value={statUnit.externalId}
    label={localize('ExternalId')}
    handleDateEdit={handleDateEdit('externalId')}
  />}
  {check('externalIdType') && <Form.Input
    value={statUnit.externalIdType}
    onChange={handleEdit('externalIdType')}
    name="name"
    label={localize('ExternalIdType')}
  />}
  {check('externalIdDate') &&
  <DatePicker
    name="externalIdDate"
    value={statUnit.externalIdDate}
    label={localize('ExternalIdDate')}
    handleDateEdit={handleDateEdit('externalIdDate')}
  />}
  {check('dataSource') && <Form.Input
    value={statUnit.dataSource}
    onChange={handleEdit('dataSource')}
    name="name"
    label={localize('DataSource')}
  />}
  {check('refNo') && <Form.Input
    value={statUnit.refNo}
    onChange={handleEdit('refNo')}
    name="name"
    label={localize('RefNo')}
  />}
  {check('name') && <Form.Input
    value={statUnit.name}
    onChange={handleEdit('name')}
    name="name"
    label={localize('Name')}
  />}
  {check('shortName') && <Form.Input
    value={statUnit.shortName}
    onChange={handleEdit('shortName')}
    name="name"
    label={localize('ShortName')}
  />}
  {check('postalAddressId') && <Form.Input
    value={statUnit.postalAddressId}
    onChange={handleEdit('postalAddressId')}
    name="name"
    label={localize('PostalAddressId')}
  />}
  {check('telephoneNo') && <Form.Input
    value={statUnit.telephoneNo}
    onChange={handleEdit('telephoneNo')}
    name="name"
    label={localize('TelephoneNo')}
  />}
  {check('emailAddress') && <Form.Input
    value={statUnit.emailAddress}
    onChange={handleEdit('emailAddress')}
    name="name"
    label={localize('Email')}
  />}
  {check('webAddress') && <Form.Input
    value={statUnit.webAddress}
    onChange={handleEdit('webAddress')}
    name="name"
    label={localize('WebAddress')}
  />}
  {check('regMainActivity') && <Form.Input
    value={statUnit.regMainActivity}
    onChange={handleEdit('regMainActivity')}
    name="name"
    label={localize('RegMainActivity')}
  />}
  {check('registrationDate') &&
  <DatePicker
    name="registrationDate"
    value={statUnit.registrationDate}
    label={localize('RegistrationDate')}
    handleDateEdit={handleDateEdit('registrationDate')}
  />}
  {check('registrationReason') && <Form.Input
    value={statUnit.registrationReason}
    onChange={handleEdit('registrationReason')}
    name="name"
    label={localize('RegistrationReason')}
  />}
  {check('liqDate') && <Form.Input
    value={statUnit.liqDate}
    onChange={handleEdit('liqDate')}
    name="name"
    label={localize('LiqDate')}
  />}
  {check('liqReason') && <Form.Input
    value={statUnit.liqReason}
    onChange={handleEdit('liqReason')}
    name="name"
    label={localize('LiqReason')}
  />}
  {check('suspensionStart') && <Form.Input
    value={statUnit.suspensionStart}
    onChange={handleEdit('suspensionStart')}
    name="name"
    label={localize('SuspensionStart')}
  />}
  {check('suspensionEnd') && <Form.Input
    value={statUnit.suspensionEnd}
    onChange={handleEdit('suspensionEnd')}
    name="name"
    label={localize('SuspensionEnd')}
  />}
  {check('reorgTypeCode') && <Form.Input
    value={statUnit.reorgTypeCode}
    onChange={handleEdit('reorgTypeCode')}
    name="name"
    label={localize('ReorgTypeCode')}
  />}
  {check('reorgDate') &&
  <DatePicker
    name="reorgDate"
    value={statUnit.reorgDate}
    label={localize('ReorgDate')}
    handleDateEdit={handleDateEdit('reorgDate')}
  />}
  {check('reorgReferences') && <Form.Input
    value={statUnit.reorgReferences}
    onChange={handleEdit('reorgReferences')}
    name="name"
    label={localize('ReorgReferences')}
  />}
  {check('actualAddress') && <Form.Input
    value={statUnit.actualAddress}
    onChange={handleEdit('actualAddress')}
    name="name"
    label={localize('ActualAddress')}
  />}
  {check('contactPerson') && <Form.Input
    value={statUnit.contactPerson}
    onChange={handleEdit('contactPerson')}
    name="name"
    label={localize('СontactPerson')}
  />}
  {check('employees') && <Form.Input
    value={statUnit.employees}
    onChange={handleEdit('employees')}
    name="name"
    label={localize('Employees')}
  />}
  {check('numOfPeople') && <Form.Input
    value={statUnit.numOfPeople}
    onChange={handleEdit('numOfPeople')}
    name="name"
    label={localize('NumOfPeople')}
  />}
  {check('employeesYear') &&
  <DatePicker
    name="employeesYear"
    value={statUnit.employeesYear}
    label={localize('EmployeesYear')}
    handleDateEdit={handleDateEdit('employeesYear')}
  />}
  {check('employeesDate') &&
  <DatePicker
    name="employeesDate"
    value={statUnit.employeesDate}
    label={localize('EmployeesDate')}
    handleDateEdit={handleDateEdit('employeesDate')}
  />}
  {check('turnover') && <Form.Input
    value={statUnit.turnover}
    onChange={handleEdit('turnover')}
    name="name"
    label={localize('Turnover')}
  />}
  {check('turnoverYear') &&
  <DatePicker
    name="turnoverYear"
    value={statUnit.turnoverYear}
    label={localize('TurnoverYear')}
    handleDateEdit={handleDateEdit('turnoverYear')}
  />}
  {check('turnoveDate') &&
  <DatePicker
    name="turnoveDate"
    value={statUnit.turnoveDate}
    label={localize('TurnoveDate')}
    handleDateEdit={handleDateEdit('turnoveDate')}
  />}
  {check('status') && <Form.Input
    value={statUnit.status}
    onChange={handleEdit('status')}
    name="status"
    label={localize('Status')}
  />}
  {check('statusDate') &&
  <DatePicker
    name="statusDate"
    value={statUnit.statusDate}
    label={localize('StatusDate')}
    handleDateEdit={handleDateEdit('statusDate')}
  />}
  {check('notes') && <Form.Input
    value={statUnit.notes}
    onChange={handleEdit('notes')}
    name="notes"
    label={localize('Notes')}
  />}
  {check('freeEconZone') && <Form.Input
    value={statUnit.freeEconZone}
    onChange={handleEdit('freeEconZone')}
    name="freeEconZone"
    label={localize('FreeEconZone')}
  />}
  {check('foreignParticipation') && <Form.Input
    value={statUnit.foreignParticipation}
    onChange={handleEdit('foreignParticipation')}
    name="foreignParticipation"
    label={localize('ForeignParticipation')}
  />}
  {check('classified') && <Form.Input
    value={statUnit.classified}
    onChange={handleEdit('classified')}
    name="classified"
    label={localize('Classified')}
  />}
  {check('isDeleted') && <Form.Input
    value={statUnit.isDeleted}
    onChange={handleEdit('isDeleted')}
    name="isDeleted"
    label={localize('IsDeleted')}
  />}
</div>)
const { func } = React.PropTypes

EditStatUnit.propTypes = {
  handleEdit: func.isRequired,
  handleDateEdit: func.isRequired,
}

EditStatUnit.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(EditStatUnit)
