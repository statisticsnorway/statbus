import React from 'react'
import { Link } from 'react-router'
import { Button, Icon } from 'semantic-ui-react'

import { formatDateTime as parseFormat } from 'helpers/dateHelper'
import { wrapper } from 'helpers/locale'
import statUnitTypes from 'helpers/statUnitTypes'
import styles from './styles.pcss'
import ViewEnterpriseGroup from './ViewEnterpriseGroup'
import ViewEnterpriseUnit from './ViewStatisticalUnit'
import ViewLegalUnit from './ViewLegalUnit'
import ViewLocalUnit from './ViewLocalUnit'

const { number, shape, string } = React.PropTypes

const View = ({ unit, localize, legalUnitOptions,
  enterpriseUnitOptions, enterpriseGroupOptions }) => (
    <div>
      <h2>{localize(`View${statUnitTypes.get(unit.type)}`)}</h2>
      {unit.type === 1 && <ViewLocalUnit {...{ unit, legalUnitOptions, enterpriseUnitOptions }} />}
      {unit.type === 2 && <ViewLegalUnit {...{ unit, enterpriseUnitOptions }} />}
      {unit.type === 3 && <ViewEnterpriseUnit {...{ unit, enterpriseGroupOptions }} />}
      {unit.type === 4 && <ViewEnterpriseGroup {...{ unit }} />}
      <br />
      <Button
        as={Link} to="/statunits"
        content={localize('Back')}
        icon={<Icon size="large" name="chevron left" />}
        size="small"
        color="gray"
        type="button"
      />
    </div>
)

View.propTypes = {
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

View.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(View)
