import React, { PropTypes } from 'react'

import { wrapper } from 'helpers/locale'
import styles from './styles.pcss'
import ViewStatisticalUnit from './ViewStatisticalUnit'

const ViewEnterpriseGroup = ({ unit, localize }) => (
  <div>
    <ViewStatisticalUnit {...{ unit, localize }} />
    <div className={styles.outer}>
      {/* EnterpriseGroup entity */}
      {unit.notes && <p><strong>{localize('Notes')}:</strong> {unit.notes}</p>}
    </div>
  </div>
)

ViewEnterpriseGroup.propTypes = {}

export default wrapper(ViewEnterpriseGroup)
