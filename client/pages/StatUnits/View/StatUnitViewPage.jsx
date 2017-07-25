import React from 'react'
import { number, shape, string, func, oneOfType, arrayOf } from 'prop-types'
import R from 'ramda'
import { Button, Icon, Menu, Segment, Loader } from 'semantic-ui-react'

import Printable from 'components/Printable/Printable'
import statUnitTypes from 'helpers/statUnitTypes'
import { Main, History, Activity, OrgLinks, Links } from './tabs'
import tabEnum from './tabs/tabEnum'

const tabs = [
  { name: 'Main', icon: 'home', tabItem: tabEnum.main },
  { name: 'Links', icon: 'chain', tabItem: tabEnum.links },
  { name: 'OrgLinks', icon: 'circle', tabItem: tabEnum.orglinks },
  { name: 'Activity', icon: 'cubes', tabItem: tabEnum.activity },
  { name: 'History', icon: 'history', tabItem: tabEnum.history },
  { name: 'Print', icon: 'print', tabItem: tabEnum.print },
]

class StatUnitViewPage extends React.Component {

  static propTypes = {
    id: oneOfType([number, string]).isRequired,
    type: oneOfType([number, string]).isRequired,
    unit: shape({
      regId: number,
      type: number.isRequired,
      name: string.isRequired,
      address: shape({
        addressLine1: string,
        addressLine2: string,
      }),
    }),
    history: shape({}),
    historyDetails: shape({}),
    legalUnitOptions: arrayOf(shape({})),
    enterpriseUnitOptions: arrayOf(shape({})),
    enterpriseGroupOptions: arrayOf(shape({})),
    actions: shape({
      fetchStatUnit: func.isRequired,
      fetchLocallUnitsLookup: func.isRequired,
      fetchLegalUnitsLookup: func.isRequired,
      fetchEnterpriseUnitsLookup: func.isRequired,
      fetchEnterpriseGroupsLookup: func.isRequired,
      fetchHistory: func.isRequired,
      fetchHistoryDetails: func.isRequired,
      fetchCountryName: func.isRequired,
      getUnitLinks: func.isRequired,
      getOrgLinks: func.isRequired,
      navigateBack: func.isRequired,
    }).isRequired,
    localize: func.isRequired,
  }

  static defaultProps = {
    unit: undefined,
    history: undefined,
    historyDetails: undefined,
    legalUnitOptions: [],
    enterpriseUnitOptions: [],
    enterpriseGroupOptions: [],
  }

  state = { activeTab: tabEnum.main }

  componentDidMount() {
    const {
      id,
      type,
      actions: {
        fetchStatUnit,
        fetchLocallUnitsLookup,
        fetchLegalUnitsLookup,
        fetchEnterpriseUnitsLookup,
        fetchEnterpriseGroupsLookup,
        fetchCountryName,
      },
    } = this.props
    fetchStatUnit(type, id)
      .then(() => fetchLocallUnitsLookup())
      .then(() => fetchLegalUnitsLookup())
      .then(() => fetchEnterpriseUnitsLookup())
      .then(() => fetchEnterpriseGroupsLookup())
      .then(() => fetchCountryName(type, id))
  }

  shouldComponentUpdate(nextProps, nextState) {
    return this.props.localize.lang !== nextProps.localize.lang
      || !R.equals(this.state, nextState)
      || !R.equals(this.props, nextProps)
  }

  handleTabClick = (_, { tabItem }) => {
    this.setState({ activeTab: tabItem })
  }

  renderTabMenuItem({ name, icon, tabItem }) {
    return (
      <Menu.Item
        key={name}
        name={this.props.localize(name)}
        icon={icon}
        active={this.state.activeTab === tabItem}
        onClick={this.handleTabClick}
        tabItem={tabItem}
      />
    )
  }

  renderView() {
    const {
      unit, history, localize, legalUnitOptions,
      enterpriseUnitOptions, enterpriseGroupOptions, historyDetails,
      actions: { navigateBack, fetchHistory, fetchHistoryDetails, getUnitLinks, getOrgLinks },
    } = this.props
    const idTuple = { id: unit.regId, type: unit.type }
    const isActive = (...params) => params.some(x => x === this.state.activeTab)
    return (
      <div>
        <h2>{localize(`View${statUnitTypes.get(unit.type)}`)}</h2>
        <Menu attached="top" tabular>
          {tabs.map(t => this.renderTabMenuItem(t))}
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
            btnShowCondition={isActive(tabEnum.print)}
          >
            {(isActive(tabEnum.main, tabEnum.print))
              && <Main
                unit={unit}
                legalUnitOptions={legalUnitOptions}
                enterpriseUnitOptions={enterpriseUnitOptions}
                enterpriseGroupOptions={enterpriseGroupOptions}
                localize={localize}
              />}
            {(isActive(tabEnum.links, tabEnum.print))
              && <Links filter={idTuple} fetchData={getUnitLinks} localize={localize} />}
            {(isActive(tabEnum.orglinks, tabEnum.print))
              && <OrgLinks id={unit.regId} fetchData={getOrgLinks} />}
            {(isActive(tabEnum.activity, tabEnum.print))
              && <Activity data={unit} localize={localize} />}
            {(isActive(tabEnum.history, tabEnum.print))
              && <History
                data={idTuple}
                history={history}
                historyDetails={historyDetails}
                fetchHistory={fetchHistory}
                fetchHistoryDetails={fetchHistoryDetails}
                localize={localize}
              />}
          </Printable>
        </Segment>
        <br />
        <Button
          content={localize('Back')}
          onClick={navigateBack}
          icon={<Icon size="large" name="chevron left" />}
          size="small"
          color="grey"
          type="button"
        />
      </div>
    )
  }

  render() {
    return this.props.unit === undefined
      ? <Loader active />
      : this.renderView()
  }
}

export default StatUnitViewPage
