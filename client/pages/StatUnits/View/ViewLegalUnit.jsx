import React, { PropTypes } from 'react'

import { formatDateTime as parseFormat } from 'helpers/dateHelper'
import { wrapper } from 'helpers/locale'
import styles from './styles.pcss'
import ViewStatisticalUnit from './ViewStatisticalUnit'

const ViewLegalUnit = ({unit, localize, enterpriseUnitOptions}) => {
  const enterpriseUnit = enterpriseUnitOptions.find(x => x.value === unit.enterpriseRegId)
  return (
    <div>
      <ViewStatisticalUnit {...{unit, localize}} />
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
    </div>
  )
}

ViewLegalUnit.propTypes = {}

export default wrapper(ViewLegalUnit)
