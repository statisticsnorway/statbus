import React, { PropTypes } from 'react'

import { formatDateTime as parseFormat } from 'helpers/dateHelper'
import { wrapper } from 'helpers/locale'
import styles from './styles.pcss'
import ViewStatisticalUnit from './ViewStatisticalUnit'

const ViewLocalUnit = ({unit, localize, legalUnitOptions, enterpriseUnitOptions}) => {
  const legalUnit = legalUnitOptions.find(x => x.value === unit.legalUnitId)
  const enterpriseUnit = enterpriseUnitOptions.find(x => x.value === unit.enterpriseUnitRegId);
  return (
    <div>
      <ViewStatisticalUnit {...{unit, localize}} />
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

ViewLocalUnit.propTypes = {}

export default wrapper(ViewLocalUnit)
