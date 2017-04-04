import React from 'react'
import { Link } from 'react-router'
import { Button, Icon, Table, Confirm } from 'semantic-ui-react'
import R from 'ramda'

import { systemFunction as sF } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import TableHeader from './Table/TableHeader'
import TableFooter from './Table/TableFooter'
import ListItem from './ListItem'

const { func, string, number, shape, arrayOf } = React.PropTypes

class RolesList extends React.Component {

  static propTypes = {
    localize: func.isRequired,
    toggleRole: func.isRequired,
    fetchRoles: func.isRequired,
    totalCount: number.isRequired,
    totalPages: number.isRequired,
    roles: arrayOf(shape({
      id: string.isRequired,
      name: string.isRequired,
      description: string.isRequired,
      activeUsers: number.isRequired,
      status: number.isRequired,
    })).isRequired,
  }

  state = {
    showConfirm: false,
    selectedId: undefined,
    selectedStatus: undefined,
  }

  componentDidMount() {
    this.props.fetchRoles()
  }

  shouldComponentUpdate(nextProps, nextState) {
    if (this.props.localize.lang !== nextProps.localize.lang) return true
    return !R.equals(this.props, nextProps) || !R.equals(this.state, nextState)
  }

  handleToggle = (id, status) => () => {
    this.setState({ selectedId: id, selectedStatus: status, showConfirm: true })
  }

  handleConfirm = () => {
    const id = this.state.selectedId
    const status = this.state.selectedStatus
    this.setState({ showConfirm: false, selectedId: undefined, selectedStatus: undefined })
    this.props.toggleRole(id, status ? 0 : 1)
  }

  handleCancel = () => {
    this.setState({ showConfirm: false })
  }

  renderConfirm = () => {
    const { localize, roles } = this.props
    const { name: confirmName } = roles.find(r => r.id === this.state.selectedId)
    const msgKey = this.state.selectedStatus
      ? 'DeleteRoleMessage'
      : 'UndeleteRoleMessage'
    return (
      <Confirm
        open={this.state.showConfirm}
        header={`${localize('AreYouSure')}?`}
        content={`${localize(msgKey)} "${confirmName}"?`}
        onConfirm={this.handleConfirm}
        onCancel={this.handleCancel}
      />
    )
  }

  render() {
    const {
      roles, totalCount, totalPages, localize,
    } = this.props
    return (
      <div>
        {this.state.showConfirm && this.renderConfirm()}
        <h2>{localize('RolesList')}</h2>
        {sF('RoleCreate')
          && <Button
            as={Link} to="/roles/create"
            content={localize('CreateRoleButton')}
            icon={<Icon size="large" name="universal access" />}
            size="medium"
            color="green"
          />}
        <Table selectable>
          <TableHeader localize={localize} />
          {roles && roles.map(r =>
            <ListItem key={r.id} {...r} onToggle={this.handleToggle(r.id, r.status)} />)}
          <TableFooter totalCount={totalCount} totalPages={totalPages} localize={localize} />
        </Table>
      </div>
    )
  }
}

export default wrapper(RolesList)
