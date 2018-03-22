import React from 'react'
import { number, shape, string, func, oneOfType } from 'prop-types'
import R from 'ramda'
import { Button, Icon, Menu, Segment, Loader } from 'semantic-ui-react'
import { Link } from 'react-router'

import Printable from 'components/Printable/Printable'
import { checkSystemFunction as sF } from 'helpers/config'
import { Main, History, Activity, OrgLinks, Links, ContactInfo, BarInfo } from './tabs'
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
      fetchSector: func.isRequired,
      fetchLegalForm: func.isRequired,
      fetchUnitStatus: func.isRequired,
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
    const { id, type, actions: { fetchStatUnit } } = this.props
    fetchStatUnit(type, id)
  }

  shouldComponentUpdate(nextProps, nextState) {
    return (
      this.props.localize.lang !== nextProps.localize.lang ||
      !R.equals(this.state, nextState) ||
      !R.equals(this.props, nextProps)
    )
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
      unit,
      history,
      localize,
      historyDetails,
      actions: { navigateBack, fetchHistory, fetchHistoryDetails, getUnitLinks, getOrgLinks },
    } = this.props
    const { activeTab } = this.state
    const idTuple = { id: unit.regId, type: unit.type }
    const isActive = (...params) => params.some(x => x.name === activeTab)

    const tabContent = (
      <div>
        {isActive(tabs.print) && (
          <div>
            <BarInfo unit={unit} localize={localize} activeTab={activeTab} />
          </div>
        )}

        {isActive(tabs.main, tabs.print) && (
          <div>
            <Main unit={unit} localize={localize} activeTab={activeTab} />
          </div>
        )}
        {isActive(tabs.print) && (
          <div>
            <br />
            <br />
          </div>
        )}
        {isActive(tabs.links, tabs.print) && (
          <Links
            filter={idTuple}
            fetchData={getUnitLinks}
            localize={localize}
            activeTab={activeTab}
          />
        )}
        {isActive(tabs.print) && (
          <div>
            <br />
          </div>
        )}
        {isActive(tabs.links) &&
          sF('LinksCreate') && (
            <div>
              <br />
              <Button
                as={Link}
                to={`/statunits/links/create?id=${idTuple.id}&type=${idTuple.type}`}
                content={localize('LinksViewAddLinkBtn')}
                positive
                floated="right"
              />
              <br />
              <br />
            </div>
          )}
        {isActive(tabs.print) && (
          <div>
            <br />
          </div>
        )}
        {isActive(tabs.orgLinks, tabs.print) && (
          <OrgLinks
            id={unit.regId}
            fetchData={getOrgLinks}
            localize={localize}
            activeTab={activeTab}
          />
        )}
        {isActive(tabs.print) && (
          <div>
            <br />
            <br />
          </div>
        )}
        {isActive(tabs.activity, tabs.print) && (
          <Activity data={unit.activities} localize={localize} activeTab={activeTab} />
        )}
        {isActive(tabs.print) && (
          <div>
            <br />
            <br />
          </div>
        )}
        {isActive(tabs.contactInfo, tabs.print) && (
          <ContactInfo data={unit} localize={localize} activeTab={activeTab} />
        )}
        {isActive(tabs.print) && (
          <div>
            <br />
            <br />
          </div>
        )}
        {isActive(tabs.history, tabs.print) && (
          <History
            data={idTuple}
            history={history}
            historyDetails={historyDetails}
            fetchHistory={fetchHistory}
            fetchHistoryDetails={fetchHistoryDetails}
            localize={localize}
            activeTab={activeTab}
          />
        )}
      </div>
    )

    return (
      <div>
        {activeTab !== 'print' && <BarInfo unit={unit} localize={localize} />}
        <Menu attached="top" tabular>
          {tabList.map(this.renderTabMenuItem)}
        </Menu>
        <Segment attached="bottom">
          {isActive(tabs.print) ? (
            <Printable
              btnPrint={
                <Button
                  content={localize('Print')}
                  icon={<Icon size="large" name="print" />}
                  size="small"
                  color="teal"
                  type="button"
                  floated="right"
                />
              }
              btnShowCondition
            >
              {tabContent}
            </Printable>
          ) : (
            tabContent
          )}
        </Segment>

        <Button
          content={localize('Back')}
          onClick={navigateBack}
          icon={<Icon size="large" name="chevron left" />}
          size="small"
          color="grey"
          type="button"
          floated="left"
        />
      </div>
    )
  }

  render() {
    return this.props.unit === undefined ? <Loader active /> : this.renderView()
  }
}

export default StatUnitViewPage
