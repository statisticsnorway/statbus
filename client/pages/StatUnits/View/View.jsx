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
  enterpriseUnitOptions, enterpriseGroupOptions, activeTab, handleTabClick }) => (<div>
    <h2>{localize(`View${statUnitTypes.get(unit.type)}`)}</h2>
    <Menu attached="top" tabular>
      <Menu.Item name={localize('Main')} active={activeTab === tabEnum.main} onClick={handleTabClick} tabItem={tabEnum.main} />
      <Menu.Item name={localize('Links')} active={activeTab === tabEnum.links} onClick={handleTabClick} tabItem={tabEnum.links} />
      <Menu.Item name={localize('Activity')} active={activeTab === tabEnum.activity} onClick={handleTabClick} tabItem={tabEnum.activity} />
      <Menu.Item name={localize('History')} active={activeTab === tabEnum.history} onClick={handleTabClick} tabItem={tabEnum.history} />
      <Menu.Item name={localize('Print')} active={activeTab === tabEnum.print} onClick={handleTabClick} tabItem={tabEnum.print} />
    </Menu>
    <Segment id="print-frame" attached="bottom">
      {(activeTab === tabEnum.main || activeTab === tabEnum.print) && <Main {...{ unit, legalUnitOptions, enterpriseUnitOptions, enterpriseGroupOptions }} />}
      {(activeTab === tabEnum.links || activeTab === tabEnum.print) && <Links />}
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
