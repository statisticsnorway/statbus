import React from 'react'
import { Form, Checkbox } from 'semantic-ui-react'

import statUnitTypes from 'helpers/statUnitTypes'
import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import DatePicker from 'components/DatePicker'
import CreateLocalUnit from './CreateLocalUnit'
import CreateLegalUnit from './CreateLegalUnit'
import CreateEnterpriseUnit from './CreateEnterpriseUnit'

const CreateStatUnit = ({ statUnit, handleEdit, handleDateEdit, handleSelectEdit, localize, statUnitTypeOptions,
  legalUnitOptions, enterpriseUnitOptions, enterpriseGroupOptions }) => (
    <div>
      <h2>{`Create ${localize(statUnitTypes.get(statUnit.type))}`}</h2>
      <Form.Select
        name="type"
        label={localize('Type')}
        options={statUnitTypeOptions}
        value={statUnit.type}
        onChange={handleSelectEdit}
      />
      {check('statId') && <Form.Input
        value={statUnit.statId}
        onChange={handleEdit('statId')}
        name="statId"
        label={localize('StatId')}
        defaultValue="0"
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
        defaultValue="0"
      />}
      {check('taxRegDate') &&
      <DatePicker
        name="taxRegDate"
        value={statUnit.taxRegDate}
        label={localize('TaxRegDate')}
        handleDateEdit={handleDateEdit('taxRegDate')}
      />}
      {check('externalId') &&
      <Form.Input
        value={statUnit.externalId}
        onChange={handleEdit('externalId')}
        name="externalId"
        label={localize('ExternalId')}
        defaultValue="0"
      />}
      {check('externalIdType') && <Form.Input
        value={statUnit.externalIdType}
        onChange={handleEdit('externalIdType')}
        name="externalIdType"
        label={localize('ExternalIdType')}
        defaultValue="0"
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
      {check('refNo') && <Form.Input
        value={statUnit.refNo}
        onChange={handleEdit('refNo')}
        name="refNo"
        label={localize('RefNo')}
        defaultValue="0"
      />}
      {check('name') && <Form.Input
        value={statUnit.name}
        onChange={handleEdit('name')}
        name="name"
        required
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
        defaultValue="0"
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
      {check('regMainActivity') && <Form.Input
        value={statUnit.regMainActivity}
        onChange={handleEdit('regMainActivity')}
        name="regMainActivity"
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
        name="registrationReason"
        label={localize('RegistrationReason')}
      />}
      {check('liqDate') && <Form.Input
        value={statUnit.liqDate}
        onChange={handleEdit('liqDate')}
        name="liqDate"
        label={localize('LiqDate')}
      />}
      {check('liqReason') && <Form.Input
        value={statUnit.liqReason}
        onChange={handleEdit('liqReason')}
        name="liqReason"
        label={localize('LiqReason')}
        defaultValue={null}
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
        defaultValue="0"
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
      {check('actualAddress') && <Form.Input
        value={statUnit.actualAddress}
        onChange={handleEdit('actualAddress')}
        name="actualAddress"
        label={localize('ActualAddress')}
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
        defaultValue="0"
      />}
      {check('numOfPeople') && <Form.Input
        value={statUnit.numOfPeople}
        onChange={handleEdit('numOfPeople')}
        name="numOfPeople"
        label={localize('NumOfPeople')}
        defaultValue="0"
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
        name="turnover"
        label={localize('Turnover')}
        defaultValue="0"
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
        defaultValue="0"
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
      {check('freeEconZone') &&
      <Checkbox
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
      {statUnit.type === 1 &&
      <CreateLocalUnit
        {...{
          statUnit,
          handleEdit,
          handleDateEdit,
          handleSelectEdit,
          legalUnitOptions,
          enterpriseUnitOptions,
          enterpriseGroupOptions,
        }}
      /> }
      {statUnit.type === 2 &&
      <CreateLegalUnit
        {...{
          statUnit,
          handleEdit,
          handleDateEdit,
          handleSelectEdit,
          legalUnitOptions,
          enterpriseUnitOptions,
          enterpriseGroupOptions,
        }}
      /> }
      {statUnit.type === 3 &&
      <CreateEnterpriseUnit
        {...{
          statUnit,
          handleEdit,
          handleDateEdit,
          handleSelectEdit,
          legalUnitOptions,
          enterpriseUnitOptions,
          enterpriseGroupOptions,
        }}
      /> }
    </div>
)

const { func } = React.PropTypes

CreateStatUnit.propTypes = {
  handleEdit: func.isRequired,
  handleDateEdit: func.isRequired,
}

CreateStatUnit.propTypes = { }

export default wrapper(CreateStatUnit)
