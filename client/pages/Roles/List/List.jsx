import React from 'react'
import { Link } from 'react-router'
import { Button, Loader, Table } from 'semantic-ui-react'

import { systemFunction as sF } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import UsersList from './UsersList'
import TableHeader from './Table/TableHeader'
import TableFooter from './Table/TableFooter'
import styles from './styles'

const Item = ({ id, name, description, deleteRole, localize, fetchRoleUsers }) => {
  const handleDelete = () => {
    if (confirm(`'${localize('DeleteRoleMessage')}'  '${name}'. '${localize('AreYouSure')}'?`)) {
      deleteRole(id)
    }
  }
  const handleFetchUsers = () => {
    fetchRoleUsers(id)
  }
  const bodyTable = () => (
    <Table.Body>
      <Table.Row>
        <Table.Cell>
          {sF('RoleEdit')
            ? <Link to={`/roles/edit/${id}`}>{ name }</Link>
            : <span> { name }</span>}
        </Table.Cell>
        <Table.Cell>{ description }</Table.Cell>
        <Table.Cell>
          <Button
            onClick={handleFetchUsers}
            color="teal"
            content={localize('Users')}
            icon="users"
          />
          <Button.Group>
            {sF('RoleDelete')
              && <Button onClick={handleDelete} icon="delete" color="red" />}
          </Button.Group>
        </Table.Cell>
      </Table.Row>
    </Table.Body>
)

  return (
    bodyTable()
  )
}

class RolesList extends React.Component {
  componentDidMount() {
    this.props.fetchRoles()
  }
  renderRoleUsers = role => (
    <UsersList users={role.users} />
  )
  render() {
    const {
      id, roles, totalCount, totalPages, selectedRole, deleteRole, fetchRoleUsers, localize,
    } = this.props
    const role = roles.find(r => r.id === selectedRole)
    return (
      <div>
        <div className={styles['add-role']}>
          <h2>{localize('RolesList')}</h2>
          {sF('RoleCreate')
              && <Button
                as={Link} to="/roles/create"
                content={localize('CreateRoleButton')}
                icon="large universal access"
                size="medium"
                color="green"
              />}
        </div>

        <div className={styles['root-row']}>
          <div className={styles['roles-table']}>
            <Loader active={status === 1} />
            <Table selectable>
              <TableHeader />
              {roles && roles.map(r =>
                <Item key={r.id} {...{ ...r, deleteRole, fetchRoleUsers, localize }} />)}
              <TableFooter totalCount={totalCount} totalPages={totalPages} />
            </ Table>
          </div>

          <div className={styles['users-table']}>
            <Table selectable>
              <Table.Header>
                <Table.Row>
                  <Table.HeaderCell textAlign="center">Users</Table.HeaderCell>
                </Table.Row>
              </Table.Header>
              <Table.Body>
                <Table.Row>
                  <Table.Cell>{role && role.users && this.renderRoleUsers(role)}</Table.Cell>
                </Table.Row>
              </Table.Body>
            </ Table>
          </ div>
        </div>
      </div>
    )
  }
}

Item.propTypes = { localize: React.PropTypes.func.isRequired }
RolesList.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(RolesList)
