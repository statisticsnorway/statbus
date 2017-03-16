import React from 'react'
import { Link } from 'react-router'
import { Button, Icon, Menu, Segment } from 'semantic-ui-react'

// import { formatDateTime as parseFormat } from 'helpers/dateHelper'
import { wrapper } from 'helpers/locale'
import statUnitTypes from 'helpers/statUnitTypes'
import tabEnum from './tabs/tabs'
import Main from './tabs/Main'
import Links from './tabs/Links'

const { number, shape, string, func } = React.PropTypes
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
  enterpriseUnitOptions, enterpriseGroupOptions, activeTab, handleTabClick }) => (
    <div>
      <Menu attached="top" tabular>
        <Menu.Item name={tabEnum.main} active={activeTab === tabEnum.main} onClick={handleTabClick} />
        <Menu.Item name={tabEnum.links} active={activeTab === tabEnum.links} onClick={handleTabClick} />
        <Menu.Item name={tabEnum.activity} active={activeTab === tabEnum.activity} onClick={handleTabClick} />
        <Menu.Item name={tabEnum.history} active={activeTab === tabEnum.history} onClick={handleTabClick} />
        <Menu.Item name={tabEnum.print} active={activeTab === tabEnum.print} onClick={handleTabClick} />
      </Menu>
      <Segment id="print-frame" attached="bottom">
        <h2>{localize(`View${statUnitTypes.get(unit.type)}`)}</h2>
        <Main {...{ unit, legalUnitOptions, enterpriseUnitOptions, enterpriseGroupOptions }} />
        <Links />
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
  handleTabClick: func.isRequired,
}
View.propTypes = { localize: func.isRequired }

export default wrapper(View)
