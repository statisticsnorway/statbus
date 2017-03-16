import React from 'react'
import { Link } from 'react-router'
import { Button, Icon, Menu, Segment } from 'semantic-ui-react'

import { formatDateTime as parseFormat } from 'helpers/dateHelper'
import { wrapper } from 'helpers/locale'
import statUnitTypes from 'helpers/statUnitTypes'
import styles from './styles.pcss'
import ViewEnterpriseGroup from './ViewEnterpriseGroup'
import ViewEnterpriseUnit from './ViewStatisticalUnit'
import ViewLegalUnit from './ViewLegalUnit'
import ViewLocalUnit from './ViewLocalUnit'
import tabEnum from './tabs/tabs'

const { number, shape, string } = React.PropTypes
const print = () => {
  const content = document.getElementById('print-frame')
  const pri = document.getElementById('ifmcontentstoprint').contentWindow
  pri.document.open()
  pri.document.write(content.innerHTML)
  pri.document.close()
  pri.focus()
  pri.print()
}
const frameStyle = {
  height: '0px',
  width: '0px',
  position: 'absolute',
}

const View = ({ unit, localize, legalUnitOptions,
  enterpriseUnitOptions, enterpriseGroupOptions, activeTab }) => (
    <div>
      <Menu attached="top" tabular>
        <Menu.Item name="main" active={activeTab === tabEnum.main} />
        <Menu.Item name="links" active={activeTab === tabEnum.links} />
        <Menu.Item name="activity" active={activeTab === tabEnum.activity} />
        <Menu.Item name="history" active={activeTab === tabEnum.history} />
        <Menu.Item name="print" active={activeTab === tabEnum.print} />
      </Menu>
      <Segment id="print-frame" attached="bottom">
        <h2>{localize(`View${statUnitTypes.get(unit.type)}`)}</h2>
        {unit.type === 1 &&
          <ViewLocalUnit {...{ unit, legalUnitOptions, enterpriseUnitOptions }} />}
        {unit.type === 2 && <ViewLegalUnit {...{ unit, enterpriseUnitOptions }} />}
        {unit.type === 3 && <ViewEnterpriseUnit {...{ unit, enterpriseGroupOptions }} />}
        {unit.type === 4 && <ViewEnterpriseGroup {...{ unit }} />}
      </Segment>
      <iframe
        id="ifmcontentstoprint"
        style={frameStyle}
      />
      <br />
      <Button
        as={Link} to="/statunits"
        content={localize('Back')}
        icon={<Icon size="large" name="chevron left" />}
        size="small"
        color="grey"
        type="button"
      />
      <Button
        onClick={print}
        content={localize('Print')}
        icon={<Icon size="large" name="print" />}
        size="small"
        color="grey"
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
  activeTab: string.isRequired,
}
View.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(View)
