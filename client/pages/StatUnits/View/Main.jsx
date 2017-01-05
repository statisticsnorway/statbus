import React from 'react'

import { formatDateTime as parseFormat } from 'helpers/dateHelper'
import { wrapper } from 'helpers/locale'
import statUnitTypes from 'helpers/statUnitTypes'
import styles from './styles'

const { number, shape, string } = React.PropTypes

const MainView = ({ unit, localize }) => (
  <div>
    <h2>{localize(`View${statUnitTypes.get(unit.type)}`)}</h2>
    <div className={styles.outer}>
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
          {typeof (unit.externalIdType) === 'number' && <p><strong>{localize('ExternalIdType')}:</strong> {unit.externalIdType}</p>}
          {unit.externalIdDate && <p><strong>{localize('ExternalIdDate')}:</strong> {parseFormat(unit.externalIdDate)}</p>}
          {unit.dataSource && <p><strong>{localize('DataSource')}:</strong> {unit.dataSource}</p>}
          {typeof (unit.refNo) === 'number' && <p><strong>{localize('RefNo')}:</strong> {unit.refNo}</p>}
          {unit.name && <p><strong>{localize('Name')}:</strong> {unit.name}</p>}
          {unit.shortName && <p><strong>{localize('ShortName')}:</strong> {unit.shortName}</p>}
          {unit.address && <p><strong>{localize('Address')}:</strong> `${unit.address.addressLine1} ${unit.address.addressLine2}`</p>}
          {typeof (unit.postalAddressId) === 'number' && <p><strong>{localize('PostalAddressId')}:</strong> {unit.postalAddressId}</p>}
        </div>
        <div className={styles.right}>
          {unit.telephoneNo && <p><strong>{localize('TelephoneNo')}:</strong> {unit.telephoneNo}</p>}
          {unit.emailAddress && <p><strong>{localize('Email')}:</strong> {unit.emailAddress}</p>}
          {unit.webAddress && <p><strong>{localize('WebAddress')}:</strong> {unit.webAddress}</p>}
          {unit.regMainActivity && <p><strong>{localize('RegMainActivity')}:</strong> {unit.regMainActivity}</p>}
          {unit.registrationDate && <p><strong>{localize('RegistrationDate')}:</strong> {parseFormat(unit.registrationDate)}</p>}
          {unit.registrationReason && <p><strong>{localize('RegistrationReason')}:</strong> {unit.registrationReason}</p>}
          {unit.liqDate && <p><strong>{localize('LiqDate')}:</strong> {unit.liqDate}</p>}
          {unit.liqReason && <p><strong>{localize('LiqReason')}:</strong> {unit.liqReason}</p>}
          {unit.suspensionStart && <p><strong>{localize('SuspensionStart')}:</strong> {unit.suspensionStart}</p>}
          {unit.suspensionEnd && <p><strong>{localize('SuspensionEnd')}:</strong> {unit.suspensionEnd}</p>}
          {unit.reorgTypeCode && <p><strong>{localize('ReorgTypeCode')}:</strong> {unit.reorgTypeCode}</p>}
          {unit.reorgDate && <p><strong>{localize('ReorgDate')}:</strong> {parseFormat(unit.reorgDate)}</p>}
          {unit.reorgReferences && <p><strong>{localize('ReorgReferences')}:</strong> {unit.reorgReferences}</p>}
          {unit.actualAddress && <p><strong>{localize('ActualAddress')}:</strong> `${unit.actualAddress.addressLine1} ${unit.actualAddress.addressLine2}
          ${unit.actualAddress.addressLine3} ${unit.actualAddress.addressLine4} ${unit.actualAddress.addressLine5}`</p>}
          {unit.contactPerson && <p><strong>{localize('ContactPerson')}:</strong> {unit.contactPerson}</p>}
          {typeof (unit.employees) === 'number' && <p><strong>{localize('Employees')}:</strong> {unit.employees}</p>}
          {typeof (unit.numOfPeople) === 'number' && <p><strong>{localize('NumOfPeople')}:</strong> {unit.numOfPeople}</p>}
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
      {unit.foreignParticipation && <p><strong>{localize('ForeignParticipation')}:</strong> {unit.foreignParticipation}</p>}
      {unit.classified && <p><strong>{localize('Classified')}:</strong> {unit.classified}</p>}
      {unit.isDeleted && <p><strong>{localize('IsDeleted')}:</strong> {unit.isDeleted}</p>}

      {/* EnterpriseUnit entity */}
      {unit.entGroupId && <p><strong>{localize('EntGroupId')}:</strong> {unit.entGroupId}</p>}
      {unit.entGroupIdDate && <p><strong>{localize('EntGroupIdDate')}:</strong> {unit.entGroupIdDate}</p>}
      {unit.commercial && <p><strong>{localize('Commercial')}:</strong> {unit.commercial}</p>}
      {unit.instSectorCode && <p><strong>{localize('InstSectorCode')}:</strong> {unit.instSectorCode}</p>}
      {unit.totalCapital && <p><strong>{localize('TotalCapital')}:</strong> {unit.totalCapital}</p>}
      {unit.munCapitalShare && <p><strong>{localize('MunCapitalShare')}:</strong> {unit.munCapitalShare}</p>}
      {unit.stateCapitalShare && <p><strong>{localize('StateCapitalShare')}:</strong> {unit.stateCapitalShare}</p>}
      {unit.privCapitalShare && <p><strong>{localize('PrivCapitalShare')}:</strong> {unit.privCapitalShare}</p>}
      {unit.foreignCapitalShare && <p><strong>{localize('ForeignCapitalShare')}:</strong> {unit.foreignCapitalShare}</p>}
      {unit.foreignCapitalCurrency && <p><strong>{localize('ForeignCapitalCurrency')}:</strong> {unit.foreignCapitalCurrency}</p>}
      {unit.actualMainActivity1 && <p><strong>{localize('ActualMainActivity1')}:</strong> {unit.actualMainActivity1}</p>}
      {unit.actualMainActivity2 && <p><strong>{localize('ActualMainActivity2')}:</strong> {unit.actualMainActivity2}</p>}
      {unit.actualMainActivityDate && <p><strong>{localize('ActualMainActivityDate')}:</strong> {unit.actualMainActivityDate}</p>}
      {unit.entGroupRole && <p><strong>{localize('EntGroupRole')}:</strong> {unit.entGroupRole}</p>}

      {/* LocalUnit entity */}
      {unit.legalUnitId && <p><strong>{localize('LegalUnitId')}:</strong> {unit.legalUnitId}</p>}
      {unit.legalUnitIdDate && <p><strong>{localize('LegalUnitIdDate')}:</strong> {parseFormat(unit.legalUnitIdDate)}</p>}

      {/* LegalUnit entity */}
      {unit.enterpriseRegId && <p><strong>{localize('EnterpriseRegId')}:</strong> {unit.enterpriseRegId}</p>}
      {unit.entRegIdDate && <p><strong>{localize('EntRegIdDate')}:</strong> {parseFormat(unit.entRegIdDate)}</p>}
      {unit.founders && <p><strong>{localize('Founders')}:</strong> {unit.founders}</p>}
      {unit.owner && <p><strong>{localize('Owner')}:</strong> {unit.owner}</p>}
      {unit.market && <p><strong>{localize('Market')}:</strong> {unit.market}</p>}
      {unit.legalForm && <p><strong>{localize('LegalForm')}:</strong> {unit.legalForm}</p>}
      {unit.instSectorCode && <p><strong>{localize('InstSectorCode')}:</strong> {unit.instSectorCode}</p>}
      {unit.totalCapital && <p><strong>{localize('TotalCapital')}:</strong> {unit.totalCapital}</p>}
      {unit.munCapitalShare && <p><strong>{localize('MunCapitalShare')}:</strong> {unit.munCapitalShare}</p>}
      {unit.stateCapitalShare && <p><strong>{localize('StateCapitalShare')}:</strong> {unit.stateCapitalShare}</p>}
      {unit.privCapitalShare && <p><strong>{localize('PrivCapitalShare')}:</strong> {unit.privCapitalShare}</p>}
      {unit.foreignCapitalShare && <p><strong>{localize('ForeignCapitalShare')}:</strong> {unit.foreignCapitalShare}</p>}
      {unit.foreignCapitalCurrency && <p><strong>{localize('ForeignCapitalCurrency')}:</strong> {unit.foreignCapitalCurrency}</p>}
      {unit.actualMainActivity1 && <p><strong>{localize('ActualMainActivity1')}:</strong> {unit.actualMainActivity1}</p>}
      {unit.actualMainActivity2 && <p><strong>{localize('ActualMainActivity2')}:</strong> {unit.actualMainActivity2}</p>}
      {unit.actualMainActivityDate && <p><strong>{localize('ActualMainActivityDate')}:</strong> {unit.actualMainActivityDate}</p>}
    </div>
  </div>
)

MainView.propTypes = {
  unit: shape({
    regId: number.isRequired,
    type: number.isRequired,
    name: string.isRequired,
    address: shape({
      addressLine1: string,
      addressLine2: string,
    }),
  }).isRequired,
}

MainView.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(MainView)
