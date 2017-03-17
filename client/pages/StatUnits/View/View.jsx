import React from 'react'
import { Link } from 'react-router'
import { Button, Icon, Menu, Segment } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'
import statUnitTypes from 'helpers/statUnitTypes'
import tabEnum from './tabs/tabs'
import Main from './tabs/Main'
import Links from './tabs/Links'
import Activity from './tabs/Activity'
import History from './tabs/History'
import styles from './styles.pcss'

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

class View extends React.Component {
  constructor(props) {
    super(props)
    this.handleTabClick = this.handleTabClick.bind(this)
    this.propTypes = {
      unit: shape({
        regId: number.isRequired,
        type: number.isRequired,
        name: string.isRequired,
        address: shape({
          addressLine1: string,
          addressLine2: string,
        }),
      }).isRequired,
      localize: func.isRequired,
    }
    this.state = { activeTab: tabEnum.main }
  }

  handleTabClick(e, { tabItem }) {
    this.setState({ activeTab: tabItem })
  }
  render() {
    const { unit, localize, legalUnitOptions,
    enterpriseUnitOptions, enterpriseGroupOptions } = this.props
    const activeTab = this.state.activeTab

    return (<div>
      <h2>{localize(`View${statUnitTypes.get(unit.type)}`)}</h2>
      <Menu attached="top" tabular>
        <Menu.Item name={localize('Main')} active={activeTab === tabEnum.main} onClick={this.handleTabClick} tabItem={tabEnum.main} />
        <Menu.Item name={localize('Links')} active={activeTab === tabEnum.links} onClick={this.handleTabClick} tabItem={tabEnum.links} />
        <Menu.Item name={localize('Activity')} active={activeTab === tabEnum.activity} onClick={this.handleTabClick} tabItem={tabEnum.activity} />
        <Menu.Item name={localize('History')} active={activeTab === tabEnum.history} onClick={this.handleTabClick} tabItem={tabEnum.history} />
        <Menu.Item name={localize('Print')} active={activeTab === tabEnum.print} onClick={this.handleTabClick} tabItem={tabEnum.print} />
      </Menu>
      <Segment attached="bottom">
        <div id="print-frame">
          {(activeTab === tabEnum.main || activeTab === tabEnum.print) &&
            <Main {...{ unit, legalUnitOptions, enterpriseUnitOptions, enterpriseGroupOptions }} />}
          {(activeTab === tabEnum.links || activeTab === tabEnum.print) && <Links />}
          {(activeTab === tabEnum.activity || activeTab === tabEnum.print) && <Activity />}
          {(activeTab === tabEnum.history || activeTab === tabEnum.print) && <History />}
        </div>
        {activeTab === tabEnum.print &&
        <Button
          onClick={print}
          content={localize('Print')}
          icon={<Icon size="large" name="print" />}
          size="small"
          color="grey"
          type="button"
          />
        }
      </Segment>
      <iframe
        id="ifmcontentstoprint"
        className={styles.frameStyle}
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
    </div>)
  }
}

export default wrapper(View)
