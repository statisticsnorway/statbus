import React from 'react'
import { arrayOf, shape, func } from 'prop-types'
import R from 'ramda'
import shouldUpdate from 'recompose/shouldUpdate'

import Info from 'components/Info'
import { formatDateTime as parseFormat } from 'helpers/dateHelper'
import AdressView from './AddressView'
import styles from '../styles.pcss'

const Main = (
  { unit, localize },
) => {
  const info = (label, text) => <Info label={localize(label)} text={text} />
  // const enterpriseUnit = enterpriseUnitOptions.find(x => x.value === unit.enterpriseUnitRegId);
  return (
    <div>
      <div>
        {/* StatisticalUnit entity */}
        <div className={styles.main}>
          <div className={styles.left}>
            {unit.regId && info('RegId', unit.regId)}
            {unit.regIdDate && info('RegIdDate', parseFormat(unit.regIdDate))}
            {typeof (unit.statId) === 'number' && info('StatId', unit.statId)}
            {unit.statIdDate && info('StatIdDate', parseFormat(unit.statIdDate))}
            {typeof (unit.taxRegId) === 'number' && info('TaxRegId', unit.taxRegId)}
            {unit.taxRegDate && info('TaxRegDate', parseFormat(unit.taxRegDate))}
            {typeof (unit.externalId) === 'number' && info('ExternalId', unit.externalId)}
            {typeof (unit.externalIdType) === 'number' && info('ExternalIdType', unit.externalIdType)}
            {unit.externalIdDate && info('ExternalIdDate', parseFormat(unit.externalIdDate))}
            {unit.dataSource && info('DataSource', unit.dataSource)}
            {typeof (unit.refNo) === 'number' && info('RefNo', unit.refNo)}
            {unit.name && info('Name', unit.name)}
            {unit.shortName && info('ShortName', unit.shortName)}
            {unit.address && <AdressView localize={localize} addressKey="Address" address={unit.address} />}
            {typeof (unit.postalAddressId) === 'number' && info('PostalAddressId', unit.postalAddressId)}
          </div>
          <div className={styles.right}>
            {unit.telephoneNo && info('TelephoneNo', unit.telephoneNo)}
            {unit.emailAddress && info('Email', unit.emailAddress)}
            {unit.webAddress && info('WebAddress', unit.webAddress)}
            {unit.regMainActivity && info('RegMainActivity', unit.regMainActivity)}
            {unit.registrationDate && info('RegistrationDate', parseFormat(unit.registrationDate))}
            {unit.registrationReason && info('RegistrationReason', unit.registrationReason)}
            {unit.liqDate && info('LiqDate', unit.liqDate)}
            {unit.liqReason && info('LiqReason', unit.liqReason)}
            {unit.suspensionStart && info('SuspensionStart', unit.suspensionStart)}
            {unit.suspensionEnd && info('SuspensionEnd', unit.suspensionEnd)}
            {unit.reorgTypeCode && info('ReorgTypeCode', unit.reorgTypeCode)}
            {unit.reorgDate && info('ReorgDate', parseFormat(unit.reorgDate))}
            {unit.reorgReferences && info('ReorgReferences', unit.reorgReferences)}
            {unit.actualAddress && <AdressView localize={localize} addressKey="ActualAddress" address={unit.actualAddress} />}
            {unit.contactPerson && info('ContactPerson', unit.contactPerson)}
            {typeof (unit.employees) === 'number' && info('Employees', unit.employees)}
            {typeof (unit.numOfPeople) === 'number' && info('NumOfPeople', unit.numOfPeople)}
            {unit.employeesYear && info('EmployeesYear', parseFormat(unit.employeesYear))}
            {unit.employeesDate && info('EmployeesDate', parseFormat(unit.employeesDate))}
            {typeof (unit.turnover) === 'number' && info('Turnover', unit.turnover)}
            {unit.turnoverYear && info('TurnoverYear', parseFormat(unit.turnoverYear))}
            {unit.turnoverDate && info('TurnoverDate', parseFormat(unit.turnoverDate))}
            {typeof (unit.status) === 'number' && info('Status', unit.status)}
            {unit.statusDate && info('StatusDate', parseFormat(unit.statusDate))}
          </div>
        </div>
        {unit.freeEconZone && info('FreeEconZone', unit.freeEconZone)}
        {unit.foreignParticipationCountryId && info('ForeignParticipationCountryId', unit.foreignParticipationCountryId)}
        {unit.foreignParticipation && info('ForeignParticipation', unit.foreignParticipation)}
        {unit.classified && info('Classified', unit.classified)}
        {unit.isDeleted && info('IsDeleted', unit.isDeleted)}
      </div>
      <div className={styles.outer}>
        {/* EnterpriseUnit entity */}
        {unit.entGroupIdDate && info('EntGroupIdDate', unit.entGroupIdDate)}
        {unit.commercial && info('Commercial', unit.commercial)}
        {unit.instSectorCode && info('InstSectorCode', unit.instSectorCode)}
        {unit.totalCapital && info('TotalCapital', unit.totalCapital)}
        {unit.munCapitalShare && info('MunCapitalShare', unit.munCapitalShare)}
        {unit.stateCapitalShare && info('StateCapitalShare', unit.stateCapitalShare)}
        {unit.privCapitalShare && info('PrivCapitalShare', unit.privCapitalShare)}
        {unit.foreignCapitalShare && info('ForeignCapitalShare', unit.foreignCapitalShare)}
        {unit.foreignCapitalCurrency && info('ForeignCapitalCurrency', unit.foreignCapitalCurrency)}
        {unit.actualMainActivity1 && info('ActualMainActivity1', unit.actualMainActivity1)}
        {unit.actualMainActivity2 && info('ActualMainActivity2', unit.actualMainActivity2)}
        {unit.actualMainActivityDate && info('ActualMainActivityDate', unit.actualMainActivityDate)}
        {unit.entGroupRole && info('EntGroupRole', unit.entGroupRole)}
      </div>
      <div className={styles.outer}>
        {/* LegalUnit entity */}
        {unit.entRegIdDate && info('EntRegIdDate', parseFormat(unit.entRegIdDate))}
        {unit.founders && info('Founders', unit.founders)}
        {unit.owner && info('Owner', unit.owner)}
        {unit.market && info('Market', unit.market)}
        {unit.legalForm && info('LegalForm', unit.legalForm)}
        {unit.instSectorCode && info('InstSectorCode', unit.instSectorCode)}
        {unit.totalCapital && info('TotalCapital', unit.totalCapital)}
        {unit.munCapitalShare && info('MunCapitalShare', unit.munCapitalShare)}
        {unit.stateCapitalShare && info('StateCapitalShare', unit.stateCapitalShare)}
        {unit.privCapitalShare && info('PrivCapitalShare', unit.privCapitalShare)}
        {unit.foreignCapitalShare && info('ForeignCapitalShare', unit.foreignCapitalShare)}
        {unit.foreignCapitalCurrency && info('ForeignCapitalCurrency', unit.foreignCapitalCurrency)}
        {unit.actualMainActivity1 && info('ActualMainActivity1', unit.actualMainActivity1)}
        {unit.actualMainActivity2 && info('ActualMainActivity2', unit.actualMainActivity2)}
        {unit.actualMainActivityDate && info('ActualMainActivityDate', unit.actualMainActivityDate)}
      </div>
      <div className={styles.outer}>
        {/* EnterpriseGroup entity */}
        {unit.notes && info('Notes', unit.notes)}
      </div>
      <div className={styles.outer}>
        {/* LocalUnit entity */}
        {unit.legalUnitIdDate && info('LegalUnitIdDate', parseFormat(unit.legalUnitIdDate))}
      </div>
    </div>
  )
}

Main.propTypes = {
  unit: shape({}),
  localize: func.isRequired,
}

Main.defaultProps = {
  unit: undefined,
}

export const checkProps = (props, nextProps) =>
  props.localize.lang !== nextProps.localize.lang ||
  !R.equals(props, nextProps)

export default shouldUpdate(checkProps)(Main)
