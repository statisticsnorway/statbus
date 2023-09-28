import React, { useState, useEffect } from 'react'
import { number, shape, string, func, oneOfType, bool } from 'prop-types'
import * as R from 'ramda'
import { Button, Icon, Menu, Segment, Loader } from 'semantic-ui-react'
import { Link } from 'react-router'

import Printable from '/client/components/Printable/Printable'
import { checkSystemFunction as sF } from '/client/helpers/config'
import { statUnitChangeReasons } from '/client/helpers/enums'
import { Main, History, Activity, OrgLinks, Links, ContactInfo, BarInfo } from './tabs'
import tabs from './tabs/tabEnum'

function StatUnitViewPage({
  id,
  type,
  unit,
  history,
  historyDetails,
  actions: {
    fetchStatUnit,
    navigateBack,
    fetchHistory,
    fetchHistoryDetails,
    getUnitLinks,
    getOrgLinks,
    fetchSector,
    fetchLegalForm,
    fetchUnitStatus,
    clear,
  },
  localize,
}) {
  const [activeTab, setActiveTab] = useState(tabs.main.name)
  const [tabList, setTabList] = useState(Object.values(tabs))

  useEffect(() => {
    fetchStatUnit(type, id)
  }, [id, type, fetchStatUnit])

  useEffect(() => {
    clear()
  }, [clear])

  const handleTabClick = (_, { name }) => {
    setActiveTab(name)
  }

  const renderTabMenuItem = ({ name, icon, label }) => (
    <Menu.Item
      key={name}
      name={name}
      content={localize(label)}
      icon={icon}
      active={activeTab === name}
      onClick={handleTabClick}
    />
  )

  const renderView = () => {
    const idTuple = { id: unit.regId, type: unit.type }
    const isActive = (...params) => params.some(x => x.name === activeTab)
    const hideLinksAndOrgLinksTabs =
      unit.isDeleted && statUnitChangeReasons.get(unit.changeReason) === 'Delete'

    if (unit !== undefined && unit.isDeleted) {
      const indexofLinks = tabList.findIndex(elem => elem.name === 'links')
      if (indexofLinks > 0) {
        tabList.splice(indexofLinks, 1)
      }
      const indexofOrgLinks = tabList.findIndex(elem => elem.name === 'orgLinks')
      if (indexofOrgLinks > 0) {
        tabList.splice(indexofOrgLinks, 1)
      }
    }

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
        {isActive(tabs.links, tabs.print) && !hideLinksAndOrgLinksTabs && (
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
        {isActive(tabs.links) && !hideLinksAndOrgLinksTabs && sF('LinksCreate') && (
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
        {isActive(tabs.print) && !hideLinksAndOrgLinksTabs && (
          <div>
            <br />
          </div>
        )}
        {isActive(tabs.orgLinks, tabs.print) && !hideLinksAndOrgLinksTabs && (
          <OrgLinks
            id={unit.regId}
            isDeletedUnit={unit.isDeleted}
            fetchData={getOrgLinks}
            localize={localize}
            activeTab={activeTab}
          />
        )}
        {isActive(tabs.print) && !hideLinksAndOrgLinksTabs && (
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
          {tabList.map(renderTabMenuItem)}
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

  if (unit === undefined) return <Loader active />
  if (this.props.errorMessage !== undefined && this.props.errorMessage.message !== '') {
    return <div>{this.props.localize(this.props.errorMessage.message)}</div>
  }
  return renderView()
}

StatUnitViewPage.propTypes = {
  id: oneOfType([number, string]).isRequired,
  type: oneOfType([number, string]).isRequired,
  unit: shape({
    regId: number,
    type: number.isRequired,
    name: string.isRequired,
    isDeleted: bool.isRequired,
    changeReason: number.isRequired,
    parentId: number,
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
    clear: func.isRequired,
  }).isRequired,
  localize: func.isRequired,
}

StatUnitViewPage.defaultProps = {
  unit: undefined,
  history: undefined,
  historyDetails: undefined,
}

export default StatUnitViewPage
