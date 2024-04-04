import React from 'react'
import { number, shape, string, func, oneOfType, bool } from 'prop-types'
import * as R from 'ramda'
import { Button, Icon, Menu, Segment, Loader, Popup, Confirm, Modal } from 'semantic-ui-react'
import { Link } from 'react-router'

import Printable from '/components/Printable/Printable'
import { checkSystemFunction as sF, checkSystemFunction as checkSF } from '/helpers/config'
import { statUnitChangeReasons, statUnitTypes } from '/helpers/enums'
import { Main, History, Activity, OrgLinks, Links, ContactInfo, BarInfo } from './tabs/index.js'
import tabs from './tabs/tabEnum.js'

import { deleteStatUnit } from '../Search/actions.js'

class StatUnitViewPage extends React.Component {
  static propTypes = {
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

  static defaultProps = {
    unit: undefined,
    history: undefined,
    historyDetails: undefined,
  }

  state = { activeTab: tabs.main.name, tabList: Object.values(tabs), showConfirmDelete: false, deleteFailed: false }

  componentDidMount() {
    const {
      id,
      type,
      actions: { fetchStatUnit },
    } = this.props
    fetchStatUnit(type, id)
  }

  shouldComponentUpdate(nextProps, nextState) {
    return (
      this.props.localize.lang !== nextProps.localize.lang ||
      !R.equals(this.state, nextState) ||
      !R.equals(this.props, nextProps)
    )
  }

  componentWillUnmount() {
    this.props.actions.clear()
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

  cancelDelete = () => {
    this.setState({ showConfirmDelete: false })
  }

  confirmDelete = () => {
    this.setState({ showConfirmDelete: true })
  }

  performDelete = (unitType, unitRegId) => {
    deleteStatUnit(unitType, unitRegId)
    .then(() => {
        // Success!
      })
      .catch(error => {
        this.setState({ deleteFailed: true })
      })
    this.setState({ showConfirmDelete: false })
  }

  clearError = () => {
    this.setState({ deleteFailed: false })
  }

  renderView() {
    const {
      unit,
      history,
      localize,
      historyDetails,
      actions: { navigateBack, fetchHistory, fetchHistoryDetails, getUnitLinks, getOrgLinks },
      statUnit,
    } = this.props
    const { activeTab } = this.state
    const idTuple = { id: unit.regId, type: unit.type }
    const isActive = (...params) => params.some(x => x.name === activeTab)
    const hideLinksAndOrgLinksTabs =
      unit.isDeleted && statUnitChangeReasons.get(unit.changeReason) === 'Delete'

    if (unit !== undefined && unit.isDeleted) {
      const indexofLinks = this.state.tabList.findIndex(elem => elem.name === 'links')
      if (indexofLinks > 0) {
        this.state.tabList.splice(indexofLinks, 1)
      }
      const indexofOrgLinks = this.state.tabList.findIndex(elem => elem.name === 'orgLinks')
      if (indexofOrgLinks > 0) {
        this.state.tabList.splice(indexofOrgLinks, 1)
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
      <Confirm
        open={this.state.showConfirmDelete}
        header={`${this.props.localize('AreYouSure')}`}
        content={`${this.props.localize('DoYouWantToDeleteUnit')} "${
          unit.name
        }"?`}
        onConfirm={() => this.performDelete(statUnitTypes.get(unit.type), unit.regId)}
        onCancel={this.cancelDelete}
        confirmButton={this.props.localize('Ok')}
        cancelButton={this.props.localize('ButtonCancel')}
      />

      <Modal
        className="errorModal"
        size="small"
        open={this.state.deleteFailed}
        onClose={this.clearError}>
        <Modal.Header>{this.props.localize('Error')}</Modal.Header>
        <Modal.Content>
          { this.props.localize('StatUnitDeleteError') }
        </Modal.Content>
        <Modal.Actions>
          <Button primary onClick={this.clearError} content={this.props.localize('Ok')} />
        </Modal.Actions>
      </Modal>

        {activeTab !== 'print' && <BarInfo unit={unit} localize={localize} />}
        <Menu attached="top" tabular>
          {this.state.tabList.map(this.renderTabMenuItem)}
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

          <Popup
            content={localize('YouDontHaveEnoughtRightsRegionOrActivity')}
            disabled={!unit.readonly}
            trigger={
              <div style={{ float: 'right', marginTop: '20px' }}>
                {checkSF('StatUnitEdit') && (
                  <Button
                    as={Link}
                    to={`/statunits/edit/${unit.type}/${unit.regId}`}
                    icon="edit"
                    primary
                    disabled={unit.readonly}
                  />
                )}
                {checkSF('StatUnitDelete') && (
                  <Button
                    onClick={() => this.confirmDelete()}
                    icon="trash"
                    negative
                    disabled={unit.readonly}
                  />
                )}
              </div>
            }
          />
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
    if (this.props.unit === undefined) return <Loader active />
    if (this.props.errorMessage !== undefined && this.props.errorMessage.message !== '') {
      return <div>{this.props.localize(this.props.errorMessage.message)}</div>
    }
    return this.renderView()
  }
}

export default StatUnitViewPage
