import React from 'react'
import { Form } from 'semantic-ui-react'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import DatePicker from 'components/DatePicker'

const EditEnterpriseGroup = ({ statUnit, handleEdit,
  handleDateEdit, localize, handleSelectEdit }) => (
  <div>
    {check('statId') &&
    <Form.Input
      value={statUnit.statId}
      onChange={handleEdit('statId')}
      name="statId"
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
      name="taxRegId"
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
      name="externalIdType"
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
      name="dataSource"
      label={localize('DataSource')}
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
      name="shortName"
      label={localize('ShortName')}
    />}
    {check('postalAddressId') && <Form.Input
      value={statUnit.postalAddressId}
      onChange={handleEdit('postalAddressId')}
      name="postalAddressId"
      label={localize('PostalAddressId')}
    />}
    {check('telephoneNo') && <Form.Input
      value={statUnit.telephoneNo}
      onChange={handleEdit('telephoneNo')}
      name="telephoneNo"
      label={localize('TelephoneNo')}
    />}
    {check('emailAddress') && <Form.Input
      value={statUnit.emailAddress}
      onChange={handleEdit('emailAddress')}
      name="emailAddress"
      label={localize('Email')}
    />}
    {check('webAddress') && <Form.Input
      value={statUnit.webAddress}
      onChange={handleEdit('webAddress')}
      name="webAddress"
      label={localize('WebAddress')}
    />}
    {check('entGroupType') && <Form.Input
      value={statUnit.entGroupType}
      onChange={handleEdit('entGroupType')}
      name="entGroupType"
      label={localize('EntGroupType')}
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
    {check('liqDateStart') && <Form.Input
      value={statUnit.liqDateStart}
      onChange={handleEdit('liqDateStart')}
      name="liqDateStart"
      label={localize('LiqDateStart')}
    />}
    {check('liqDateEnd') && <Form.Input
      value={statUnit.liqDateEnd}
      onChange={handleEdit('liqDateEnd')}
      name="liqDateEnd"
      label={localize('LiqDateEnd')}
    />}
    {check('liqReason') && <Form.Input
      value={statUnit.liqReason}
      onChange={handleEdit('liqReason')}
      name="liqReason"
      label={localize('LiqReason')}
    />}
    {check('suspensionStart') && <Form.Input
      value={statUnit.suspensionStart}
      onChange={handleEdit('suspensionStart')}
      name="suspensionStart"
      label={localize('SuspensionStart')}
    />}
    {check('suspensionEnd') && <Form.Input
      value={statUnit.suspensionEnd}
      onChange={handleEdit('suspensionEnd')}
      name="suspensionEnd"
      label={localize('SuspensionEnd')}
    />}
    {check('reorgTypeCode') && <Form.Input
      value={statUnit.reorgTypeCode}
      onChange={handleEdit('reorgTypeCode')}
      name="reorgTypeCode"
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
      name="reorgReferences"
      label={localize('ReorgReferences')}
    />}
    {check('contactPerson') && <Form.Input
      value={statUnit.contactPerson}
      onChange={handleEdit('contactPerson')}
      name="contactPerson"
      label={localize('СontactPerson')}
    />}
    {check('employees') && <Form.Input
      value={statUnit.employees}
      onChange={handleEdit('employees')}
      name="employees"
      label={localize('Employees')}
    />}
    {check('employeesFte') && <Form.Input
      value={statUnit.employeesFte}
      onChange={handleEdit('employeesFte')}
      name="employeesFte"
      label={localize('EmployeesFte')}
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
  </div>
)

EditEnterpriseGroup.propTypes = {

}

export default wrapper(EditEnterpriseGroup)

