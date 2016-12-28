import React from 'react'
import { Button, Form } from 'semantic-ui-react'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'

class EditForm extends React.Component {
 
  componentDidMount() {
    this.props.fetchStatUnit(this.props.id)
  }
  render() {

    const { statUnit, editForm, submitStatUnit } = this.props
    const handleSubmit = () => { submitStatUnit(statUnit) }
    const handleEdit = prop => (e) => { editForm(prop, e.target.value) }
    return (
      <Form onSubmit={handleSubmit}>
        {check('statId') && <Form.Input
          value={statUnit.statId}
          onChange={handleEdit('statId')}
          name="name"
          label="StatId"
        />}
        {check('statIdDate') && <Form.Input
          value={statUnit.statIdDate}
          onChange={handleEdit('statIdDate')}
          name="name"
          label="StatIdDate"
        />}
        {check('taxRegId') && <Form.Input
          value={statUnit.taxRegId}
          onChange={handleEdit('taxRegId')}
          name="name"
          label="TaxRegId"
        />}
        {check('taxRegDate') && <Form.Input
          value={statUnit.taxRegDate}
          onChange={handleEdit('taxRegDate')}
          name="name"
          label="TaxRegDate"
        />}
        {check('externalId') && <Form.Input
          value={statUnit.taxRegDate}
          onChange={handleEdit('externalId')}
          name="name"
          label="ExternalId"
        />}
        {check('externalIdType') && <Form.Input
          value={statUnit.externalIdType}
          onChange={handleEdit('externalIdType')}
          name="name"
          label="ExternalIdType"
        />}
        {check('externalIdDate') && <Form.Input
          value={statUnit.externalIdDate}
          onChange={handleEdit('externalIdDate')}
          name="name"
          label="externalIdDate"
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
        {check('registrationDate') && <Form.Input
          value={statUnit.registrationDate}
          onChange={handleEdit('registrationDate')}
          name="name"
          label="RegistrationDate"
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
        {check('reorgDate') && <Form.Input
          value={statUnit.reorgDate}
          onChange={handleEdit('reorgDate')}
          name="name"
          label="ReorgDate"
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
        {check('employeesYear') && <Form.Input
          value={statUnit.employeesYear}
          onChange={handleEdit('employeesYear')}
          name="name"
          label="EmployeesYear"
        />}
        {check('employeesDate') && <Form.Input
          value={statUnit.employeesDate}
          onChange={handleEdit('employeesDate')}
          name="name"
          label="EmployeesDate"
        />}
        {check('turnover') && <Form.Input
          value={statUnit.turnover}
          onChange={handleEdit('turnover')}
          name="name"
          label="Turnover"
        />}
        {check('turnoverYear') && <Form.Input
          value={statUnit.turnoverYear}
          onChange={handleEdit('turnoverYear')}
          name="name"
          label="TurnoverYear"
        />}
        {check('turnoveDate') && <Form.Input
          value={statUnit.turnoveDate}
          onChange={handleEdit('turnoveDate')}
          name="name"
          label="TurnoveDate"
        />}
        {check('status') && <Form.Input
          value={statUnit.status}
          onChange={handleEdit('status')}
          name="status"
          label="Status"
        />}
        {check('statusDate') && <Form.Input
          value={statUnit.statusDate}
          onChange={handleEdit('statusDate')}
          name="statusDate"
          label="StatusDate"
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
        
        {/* EnterpriseUnit entity */}
        {statUnit.type === 1 &&
          check('isDeleted') && <Form.Input
            value={statUnit.isDeleted}
            onChange={handleEdit('isDeleted')}
            name="isDeleted"
            label="IsDeleted"
          />
        }
     
        
        <Button>submit</Button>
      </Form>
    )
  }

}

const { func, number, shape, string } = React.PropTypes

EditForm.propTypes = {
  editForm: func.isRequired,
  submitStatUnit: func.isRequired,
  fetchStatUnit: func.isRequired,
  id: string.isRequired,
}

export default EditForm
