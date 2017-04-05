import React from 'react'
import { Link } from 'react-router'
import { Button, Icon, Menu, Segment } from 'semantic-ui-react'
import Printable from 'components/Printable/Printable'
import { wrapper } from 'helpers/locale'
import statUnitTypes from 'helpers/statUnitTypes'
import tabEnum from './tabs/tabEnum'
import { Main, History, Activity, Links } from './tabs'

const { number, shape, string, func } = React.PropTypes

class View extends React.Component {

  static propTypes = {
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

  state = { activeTab: tabEnum.main }

  handleTabClick = (e, { tabItem }) => {
    this.setState({ activeTab: tabItem })
  }

  render() {
    const { unit, localize, legalUnitOptions,
    enterpriseUnitOptions, enterpriseGroupOptions, fetchHistory, history } = this.props
    const activeTab = this.state.activeTab

    return (<div>
      <h2>{localize(`View${statUnitTypes.get(unit.type)}`)}</h2>
      <Menu attached="top" tabular>
        <Menu.Item name={localize('Main')} icon="home" active={activeTab === tabEnum.main} onClick={this.handleTabClick} tabItem={tabEnum.main} />
        <Menu.Item name={localize('Links')} icon="chain" active={activeTab === tabEnum.links} onClick={this.handleTabClick} tabItem={tabEnum.links} />
        <Menu.Item name={localize('Activity')} icon="cubes" active={activeTab === tabEnum.activity} onClick={this.handleTabClick} tabItem={tabEnum.activity} />
        <Menu.Item name={localize('History')} icon="history" active={activeTab === tabEnum.history} onClick={this.handleTabClick} tabItem={tabEnum.history} />
        <Menu.Item name={localize('Print')} icon="print" active={activeTab === tabEnum.print} onClick={this.handleTabClick} tabItem={tabEnum.print} />
      </Menu>
      <Segment attached="bottom">
        <Printable
          btnPrint={
            <Button
              content={localize('Print')}
              icon={<Icon size="large" name="print" />}
              size="small"
              color="grey"
              type="button"
            />}
          btnShowCondition={activeTab === tabEnum.print} >
          {(activeTab === tabEnum.main || activeTab === tabEnum.print) &&
            <Main {...{ unit, legalUnitOptions, enterpriseUnitOptions, enterpriseGroupOptions }} />}
          {(activeTab === tabEnum.links || activeTab === tabEnum.print) && <Links />}
          {(activeTab === tabEnum.activity || activeTab === tabEnum.print) &&
            <Activity data={unit} />}
          {(activeTab === tabEnum.history || activeTab === tabEnum.print) &&
          <History fetchHistory={fetchHistory} history={history} data={{ type: unit.type, regId: unit.regId }} />}
        </Printable>
      </Segment>
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
