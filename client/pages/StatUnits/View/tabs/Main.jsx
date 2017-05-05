import React from 'react'
import R from 'ramda'
import shouldUpdate from 'recompose/shouldUpdate'

import { formatDateTime as parseFormat } from 'helpers/dateHelper'
import { wrapper } from 'helpers/locale'
import AdressView from '../Components/AddressView'
import styles from '../styles.pcss'

const Main = ({ unit, localize, enterpriseGroupOptions, enterpriseUnitOptions, legalUnitOptions }) => {
  const enterpriseGroup = enterpriseGroupOptions.find(x => x.value === unit.entGroupId)
  const enterpriseUnit = enterpriseUnitOptions.find(x => x.value === unit.enterpriseRegId)
  const legalUnit = legalUnitOptions.find(x => x.value === unit.legalUnitId)
  // const enterpriseUnit = enterpriseUnitOptions.find(x => x.value === unit.enterpriseUnitRegId);
  return (
    <div>
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
            {unit.address && <AdressView localize={localize} addressKey="Address" address={unit.address} />}
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
            {unit.actualAddress && <AdressView localize={localize} addressKey="ActualAddress" address={unit.actualAddress} />}
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
        {unit.freeEconZone && <p><strong>{localize('FreeEconZone')}:</strong> {unit.freeEconZone}</p>}
        {unit.foreignParticipation &&
          <p><strong>{localize('ForeignParticipation')}:</strong> {unit.foreignParticipation}</p>}
        {unit.classified && <p><strong>{localize('Classified')}:</strong> {unit.classified}</p>}
        {unit.isDeleted && <p><strong>{localize('IsDeleted')}:</strong> {unit.isDeleted}</p>}
      </div>
      <div className={styles.outer}>
        {/* EnterpriseUnit entity */}
        {enterpriseGroup && <p><strong>{localize('EntGroupId')}:</strong> {enterpriseGroup.text}</p>}
        {unit.entGroupIdDate && <p><strong>{localize('EntGroupIdDate')}:</strong> {unit.entGroupIdDate}</p>}
        {unit.commercial && <p><strong>{localize('Commercial')}:</strong> {unit.commercial}</p>}
        {unit.instSectorCode && <p><strong>{localize('InstSectorCode')}:</strong> {unit.instSectorCode}</p>}
        {unit.totalCapital && <p><strong>{localize('TotalCapital')}:</strong> {unit.totalCapital}</p>}
        {unit.munCapitalShare && <p><strong>{localize('MunCapitalShare')}:</strong> {unit.munCapitalShare}</p>}
        {unit.stateCapitalShare && <p><strong>{localize('StateCapitalShare')}:</strong> {unit.stateCapitalShare}</p>}
        {unit.privCapitalShare && <p><strong>{localize('PrivCapitalShare')}:</strong> {unit.privCapitalShare}</p>}
        {unit.foreignCapitalShare &&
          <p><strong>{localize('ForeignCapitalShare')}:</strong> {unit.foreignCapitalShare}</p>}
        {unit.foreignCapitalCurrency &&
          <p><strong>{localize('ForeignCapitalCurrency')}:</strong> {unit.foreignCapitalCurrency}</p>}
        {unit.actualMainActivity1 &&
          <p><strong>{localize('ActualMainActivity1')}:</strong> {unit.actualMainActivity1}</p>}
        {unit.actualMainActivity2 &&
          <p><strong>{localize('ActualMainActivity2')}:</strong> {unit.actualMainActivity2}</p>}
        {unit.actualMainActivityDate &&
          <p><strong>{localize('ActualMainActivityDate')}:</strong> {unit.actualMainActivityDate}</p>}
        {unit.entGroupRole && <p><strong>{localize('EntGroupRole')}:</strong> {unit.entGroupRole}</p>}
      </div>
      <div className={styles.outer}>
        {/* LegalUnit entity */}
        {enterpriseUnit && <p><strong>{localize('EnterpriseRegId')}:</strong> {enterpriseUnit.text}</p>}
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
        {unit.foreignCapitalShare &&
          <p><strong>{localize('ForeignCapitalShare')}:</strong> {unit.foreignCapitalShare}</p>}
        {unit.foreignCapitalCurrency &&
          <p><strong>{localize('ForeignCapitalCurrency')}:</strong> {unit.foreignCapitalCurrency}</p>}
        {unit.actualMainActivity1 &&
          <p><strong>{localize('ActualMainActivity1')}:</strong> {unit.actualMainActivity1}</p>}
        {unit.actualMainActivity2 &&
          <p><strong>{localize('ActualMainActivity2')}:</strong> {unit.actualMainActivity2}</p>}
        {unit.actualMainActivityDate &&
          <p><strong>{localize('ActualMainActivityDate')}:</strong> {unit.actualMainActivityDate}</p>}
      </div>
      <div className={styles.outer}>
        {/* EnterpriseGroup entity */}
        {unit.notes && <p><strong>{localize('Notes')}:</strong> {unit.notes}</p>}
      </div>
      <div className={styles.outer}>
        {/* LocalUnit entity */}
        {legalUnit && <p><strong>{localize('LegalUnitId')}:</strong> {legalUnit.text}</p>}
        {unit.legalUnitIdDate &&
          <p><strong>{localize('LegalUnitIdDate')}:</strong> {parseFormat(unit.legalUnitIdDate)}</p>}
        {enterpriseUnit && <p><strong>{localize('EnterpriseUnitRegId')}:</strong> {enterpriseUnit.text}</p>}
      </div>
    </div>
  )
}

const { shape, func } = React.PropTypes

Main.propTypes = {
  unit: shape(),
  localize: func.isRequired,
}

export const checkProps = (props, nextProps) =>
  props.localize.lang !== nextProps.localize.lang ||
  !R.equals(props, nextProps)

export default wrapper(shouldUpdate(checkProps)(Main))
