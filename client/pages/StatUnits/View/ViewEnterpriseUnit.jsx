import React, { PropTypes } from 'react'

import { wrapper } from 'helpers/locale'
import styles from './styles.pcss'
import ViewStatisticalUnit from './ViewStatisticalUnit'

const ViewEnterpriseUnit = ({unit, localize, enterpriseGroupOptions}) => {
  const enterpriseGroup = enterpriseGroupOptions.find(x => x.value === unit.entGroupId)
  return (
    <div>
      <ViewStatisticalUnit {...{unit, localize}} />
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
    </div>
  )
}

ViewEnterpriseUnit.propTypes = {}

export default wrapper(ViewEnterpriseUnit)
