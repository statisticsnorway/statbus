import React from 'react'
import { number, shape, string, func, oneOfType } from 'prop-types'
import R from 'ramda'
import { Button, Icon, Menu, Segment, Loader, Label, Grid } from 'semantic-ui-react'
import { Link } from 'react-router'

import Printable from 'components/Printable/Printable'
import { checkSystemFunction as sF } from 'helpers/config'
import { hasValue } from 'helpers/validation'
import { Main, History, Activity, OrgLinks, Links, ContactInfo } from './tabs'
import tabs from './tabs/tabEnum'

const tabList = Object.values(tabs)

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
    actions: shape({
      fetchStatUnit: func.isRequired,
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
  }

  state = { activeTab: tabs.main.name }

  componentDidMount() {
    const {
      id,
      type,
      actions: {
        fetchStatUnit,
        fetchCountryName,
      },
    } = this.props
    fetchStatUnit(type, id)
      .then(() => fetchCountryName(type, id))
  }

  shouldComponentUpdate(nextProps, nextState) {
    return this.props.localize.lang !== nextProps.localize.lang
      || !R.equals(this.state, nextState)
      || !R.equals(this.props, nextProps)
  }

  handleTabClick = (_, { name }) => {
    this.setState({ activeTab: name })
  }

  renderTabMenuItem = ({ name, icon, label }) => (
    <Menu.Item
      key={name}
      name={name}
      content={this.props.localize(label)}
      icon={icon}
      active={this.state.activeTab === name}
      onClick={this.handleTabClick}
    />
  )

  renderView() {
    const {
      unit, history, localize, historyDetails,
      actions: { navigateBack, fetchHistory, fetchHistoryDetails, getUnitLinks, getOrgLinks },
    } = this.props
    const idTuple = { id: unit.regId, type: unit.type }
    const isActive = (...params) => params.some(x => x.name === this.state.activeTab)
    const sorted = unit.activities.sort((a, b) => b.activityYear - a.activityYear)
    const lastActivityYear = sorted[0].activityYear
    const activityYearLastByTurnover = sorted.find(x => hasValue(x.turnover)).activityYear
    return (
      <div>
        <h2>{unit.name}</h2>
        {unit.name === unit.shortName && `(${unit.shortName})`}
        <Grid>
          <Grid.Row columns={5}>
            {unit.statId &&
              <Grid.Column >
                <Segment size="mini">
                  <Label pointing="right" size="medium">{localize('StatId')} </Label>
                  {unit.statId}
                </Segment>
              </Grid.Column>}
            {unit.taxRegId &&
              <Grid.Column width={3}>
                <Segment size="mini">
                  <Label pointing="right" size="medium">{localize('TaxRegId')} </Label>
                  {unit.taxRegId}
                </Segment>
              </Grid.Column>}
            {unit.externalIdType &&
              <Grid.Column >
                <Segment size="mini">
                  <Label pointing="right" size="medium">{localize('ExternalIdType')} </Label>
                  {unit.externalIdType}
                </Segment>
              </Grid.Column>}
            {hasValue(activityYearLastByTurnover) &&
              <Grid.Column >
                <Segment size="mini">
                  <Label pointing="right" size="medium">{localize('TurnoverYear')} </Label>
                  {activityYearLastByTurnover}
                </Segment>
              </Grid.Column>}
            {hasValue(lastActivityYear) &&
              <Grid.Column >
                <Segment size="mini">
                  <Label pointing="right" size="medium">{localize('NumEmployeeYear')} </Label>
                  {lastActivityYear}
                </Segment>
              </Grid.Column>}
          </Grid.Row>
        </Grid>
        <Menu attached="top" tabular>
          {tabList.map(this.renderTabMenuItem)}
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
            btnShowCondition={isActive(tabs.print)}
          >
            {(isActive(tabs.main, tabs.print)) &&
              <Main
                unit={unit}
                localize={localize}
              />}
            {(isActive(tabs.links, tabs.print)) &&
              <Links
                filter={idTuple}
                fetchData={getUnitLinks}
                localize={localize}
              /> }
            {(isActive(tabs.links)) && sF('LinksCreate') &&
              <Button
                as={Link}
                to={`/statunits/links/create?id=${idTuple.id}&type=${idTuple.type}`}
                content={localize('LinksViewAddLinkBtn')}
                positive
              />}
            {(isActive(tabs.orgLinks, tabs.print)) &&
              <OrgLinks id={unit.regId} fetchData={getOrgLinks} />}
            {(isActive(tabs.activity, tabs.print)) &&
              <Activity data={unit.activities} localize={localize} />}
            {(isActive(tabs.contactInfo, tabs.print)) &&
              <ContactInfo data={unit} localize={localize} />}
            {(isActive(tabs.history, tabs.print)) &&
              <History
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
