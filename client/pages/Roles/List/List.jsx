import React from 'react'
import { func, string, number, shape, arrayOf } from 'prop-types'
import { Link } from 'react-router'
import { Button, Icon, Table, Confirm } from 'semantic-ui-react'
import { equals } from 'ramda'

import Paginate from 'components/Paginate'
import { checkSystemFunction as sF } from 'helpers/config'
import TableHeader from './Table/TableHeader'
import ListItem from './ListItem'

class RolesList extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    toggleRole: func.isRequired,
    fetchRoles: func.isRequired,
    totalCount: number.isRequired,
    query: shape({}).isRequired,
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
    this.props.fetchRoles(this.props.query)
  }

  componentWillReceiveProps(nextProps) {
    if (!equals(nextProps.query, this.props.query)) {
      nextProps.fetchRoles(nextProps.query)
    }
  }

  shouldComponentUpdate(nextProps, nextState) {
    return (
      this.props.localize.lang !== nextProps.localize.lang ||
      !equals(this.props, nextProps) ||
      !equals(this.state, nextState)
    )
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
    const msgKey = this.state.selectedStatus ? 'DeleteRoleMessage' : 'UndeleteRoleMessage'
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
    const { roles, totalCount, localize } = this.props
    return (
      <div>
        {this.state.showConfirm && this.renderConfirm()}
        <h2>{localize('RolesList')}</h2>
        <Paginate totalCount={totalCount}>
          <Table selectable>
            <TableHeader localize={localize} />
            {roles &&
              roles.map(r => (
                <ListItem key={r.id} {...r} onToggle={this.handleToggle(r.id, r.status)} />
              ))}
          </Table>
        </Paginate>
      </div>
    )
  }
}

export default RolesList
