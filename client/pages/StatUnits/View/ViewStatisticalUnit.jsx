import React, { PropTypes } from 'react'

import { formatDateTime as parseFormat } from 'helpers/dateHelper'
import { wrapper } from 'helpers/locale'
import styles from './styles.pcss'

const ViewStatisticalUnit = ({ unit, localize }) => (
  <div>
    {/* StatisticalUnit entity */}
    <div className={styles.main}>
      <div className={styles.left}>
        {unit.regId && <p><strong>{localize('RegId')}:</strong> {unit.regId}</p>}
        {unit.regIdDate && <p><strong>{localize('RegIdDate')}:</strong> {parseFormat(unit.regIdDate)}</p>}
        { typeof (unit.statId) === 'number' && <p><strong>{localize('StatId')}:</strong> {unit.statId}</p>}
        {unit.statIdDate && <p><strong>{localize('StatIdDate')}:</strong> {parseFormat(unit.statIdDate)}</p>}
        {typeof (unit.taxRegId) === 'number' && <p><strong>{localize('TaxRegId')}:</strong> {unit.taxRegId}</p>}
        {unit.taxRegDate && <p><strong>{localize('TaxRegDate')}:</strong> {parseFormat(unit.taxRegDate)}</p>}
        {typeof (unit.externalId) === 'number' && <p><strong>{localize('ExternalId')}:</strong> {unit.externalId}</p>}
        {typeof (unit.externalIdType) === 'number' &&
        <p><strong>{localize('ExternalIdType')}:</strong> {unit.externalIdType}</p>}
        {unit.externalIdDate &&
        <p><strong>{localize('ExternalIdDate')}:</strong> {parseFormat(unit.externalIdDate)}</p>}
        {unit.dataSource && <p><strong>{localize('DataSource')}:</strong> {unit.dataSource}</p>}
        {typeof (unit.refNo) === 'number' && <p><strong>{localize('RefNo')}:</strong> {unit.refNo}</p>}
        {unit.name && <p><strong>{localize('Name')}:</strong> {unit.name}</p>}
        {unit.shortName && <p><strong>{localize('ShortName')}:</strong> {unit.shortName}</p>}
        {unit.address &&
        <p><strong>{localize('Address')}:</strong> `${unit.address.addressLine1} ${unit.address.addressLine2}`</p>}
        {typeof (unit.postalAddressId) === 'number' &&
        <p><strong>{localize('PostalAddressId')}:</strong> {unit.postalAddressId}</p>}
      </div>
      <div className={styles.right}>
        {unit.telephoneNo && <p><strong>{localize('TelephoneNo')}:</strong> {unit.telephoneNo}</p>}
        {unit.emailAddress && <p><strong>{localize('Email')}:</strong> {unit.emailAddress}</p>}
        {unit.webAddress && <p><strong>{localize('WebAddress')}:</strong> {unit.webAddress}</p>}
        {unit.regMainActivity && <p><strong>{localize('RegMainActivity')}:</strong> {unit.regMainActivity}</p>}
        {unit.registrationDate &&
        <p><strong>{localize('RegistrationDate')}:</strong> {parseFormat(unit.registrationDate)}</p>}
        {unit.registrationReason && <p><strong>{localize('RegistrationReason')}:</strong> {unit.registrationReason}</p>}
        {unit.liqDate && <p><strong>{localize('LiqDate')}:</strong> {unit.liqDate}</p>}
        {unit.liqReason && <p><strong>{localize('LiqReason')}:</strong> {unit.liqReason}</p>}
        {unit.suspensionStart && <p><strong>{localize('SuspensionStart')}:</strong> {unit.suspensionStart}</p>}
        {unit.suspensionEnd && <p><strong>{localize('SuspensionEnd')}:</strong> {unit.suspensionEnd}</p>}
        {unit.reorgTypeCode && <p><strong>{localize('ReorgTypeCode')}:</strong> {unit.reorgTypeCode}</p>}
        {unit.reorgDate && <p><strong>{localize('ReorgDate')}:</strong> {parseFormat(unit.reorgDate)}</p>}
        {unit.reorgReferences && <p><strong>{localize('ReorgReferences')}:</strong> {unit.reorgReferences}</p>}
        {unit.actualAddress && <p><strong>{localize('ActualAddress')}:</strong> `${unit.actualAddress.addressLine1}
          ${unit.actualAddress.addressLine2}
          ${unit.actualAddress.addressLine3} ${unit.actualAddress.addressLine4} ${unit.actualAddress.addressLine5}`</p>}
        {unit.contactPerson && <p><strong>{localize('ContactPerson')}:</strong> {unit.contactPerson}</p>}
        {typeof (unit.employees) === 'number' && <p><strong>{localize('Employees')}:</strong> {unit.employees}</p>}
        {typeof (unit.numOfPeople) === 'number' &&
        <p><strong>{localize('NumOfPeople')}:</strong> {unit.numOfPeople}</p>}
        {unit.employeesYear && <p><strong>{localize('EmployeesYear')}:</strong> {parseFormat(unit.employeesYear)}</p>}
        {unit.employeesDate && <p><strong>{localize('EmployeesDate')}:</strong> {parseFormat(unit.employeesDate)}</p>}
        {typeof (unit.turnover) === 'number' && <p><strong>{localize('Turnover')}:</strong> {unit.turnover}</p>}
        {unit.turnoverYear && <p><strong>{localize('TurnoverYear')}:</strong> {parseFormat(unit.turnoverYear)}</p>}
        {unit.turnoveDate && <p><strong>{localize('TurnoveDate')}:</strong> {parseFormat(unit.turnoveDate)}</p>}
        {typeof (unit.status) === 'number' && <p><strong>{localize('Status')}:</strong> {unit.status}</p>}
        {unit.statusDate && <p><strong>{localize('StatusDate')}:</strong> {parseFormat(unit.statusDate)}</p>}
      </div>
    </div>
    {unit.notes && <p><strong>{localize('Notes')}:</strong> {unit.notes}</p>}
    {unit.freeEconZone && <p><strong>{localize('FreeEconZone')}:</strong> {unit.freeEconZone}</p>}
    {unit.foreignParticipation &&
    <p><strong>{localize('ForeignParticipation')}:</strong> {unit.foreignParticipation}</p>}
    {unit.classified && <p><strong>{localize('Classified')}:</strong> {unit.classified}</p>}
    {unit.isDeleted && <p><strong>{localize('IsDeleted')}:</strong> {unit.isDeleted}</p>}
  </div>
)

ViewStatisticalUnit.propTypes = {}

export default wrapper(ViewStatisticalUnit)
