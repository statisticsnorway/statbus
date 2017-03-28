import React from 'react'
import { Link } from 'react-router'
import { Button, Icon, Table, Confirm } from 'semantic-ui-react'

import { systemFunction as sF } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import TableHeader from './Table/TableHeader'
import TableFooter from './Table/TableFooter'
import ListItem from './ListItem'

const { func, string, number, shape, arrayOf } = React.PropTypes

class RolesList extends React.Component {

  static propTypes = {
    localize: func.isRequired,
    deleteRole: func.isRequired,
    fetchRoles: func.isRequired,
    totalCount: number.isRequired,
    totalPages: number.isRequired,
    roles: arrayOf(shape({
      id: string.isRequired,
      name: string.isRequired,
      description: string.isRequired,
      activeUsers: number.isRequired,
    })).isRequired,
  }

  state = {
    showConfirm: false,
    selectedId: undefined,
  }

  componentDidMount() {
    this.props.fetchRoles()
  }

  handleDelete = id => () => {
    this.setState({ selectedId: id, showConfirm: true })
  }

  handleConfirm = () => {
    const id = this.state.selectedId
    this.setState({ showConfirm: false, selectedId: undefined })
    this.props.deleteRole(id)
  }

  handleCancel = () => {
    this.setState({ showConfirm: false })
  }

  renderConfirm = () => {
    const { localize, roles } = this.props
    const { name: confirmName } = roles.find(r => r.id === this.state.selectedId)
    return (
      <Confirm
        open={this.state.showConfirm}
        header={`${localize('AreYouSure')}?`}
        content={`${localize('DeleteRoleMessage')} ${confirmName}?`}
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
          <TableHeader />
          {roles && roles.map(r =>
            <ListItem key={r.id} {...r} onDelete={this.handleDelete(r.id)} />)}
          <TableFooter totalCount={totalCount} totalPages={totalPages} />
        </Table>
      </div>
    )
  }
}

export default wrapper(RolesList)
