import React from 'react'
import { Link } from 'react-router'
import { Button, Loader, Table } from 'semantic-ui-react'

import { systemFunction as sF } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import TableHeader from './Table/TableHeader'
import TableFooter from './Table/TableFooter'
import styles from './styles'

const Item = ({ id, deleteUser, ...user, localize }) => {
  const handleDelete = () => {
    if (confirm(`'${localize('DeleteUserMessage')}'  '${user.name}'. '${localize('AreYouSure')}'?`)) deleteUser(id)
  }
  const bodyTable = () => (
    <Table.Body>
      <Table.Row>
        <Table.Cell>
          {sF('UserEdit')
            ? <Link to={`/users/edit/${id}`}>{user.name}</Link>
            : <span>{user.name}</span>}
        </Table.Cell>
        <Table.Cell>{user.description}</Table.Cell>
        <Table.Cell>
          <Button.Group>
            {sF('UserDelete')
                && <Button
                  onClick={handleDelete}
                  icon="delete"
                  color="red"
                /> }
          </Button.Group>
        </Table.Cell>
      </Table.Row>
    </Table.Body>
    )
  return (
    bodyTable()
  )
}

class UsersList extends React.Component {
  componentDidMount() {
    this.props.fetchUsers()
  }
  render() {
    const { users, totalCount, totalPages, editUser, deleteUser, status, localize } = this.props
    return (
      <div>
        <div className={styles['add-user']}>
          <h2>{localize('UsersList')}</h2>
          {sF('UserCreate')
            && <Button
              as={Link} to="/users/create"
              content={localize('CreateUserButton')}
              icon="large user plus"
              size="medium"
              color="green"
            />}
        </div>
        <div className={styles['list-root']}>
          <Loader active={status === 1} />
          <div className={styles.addUser} />
          <Table singleLine selectable>
            <TableHeader />
            {users && users.map(u =>
              <Item key={u.id} {...u} deleteUser={deleteUser} locale={'locale'} />)}
            <TableFooter totalCount={totalCount} totalPages={totalPages} />
          </Table>
        </div>
      </div>
    )
  }
}

Item.propTypes = { localize: React.PropTypes.func.isRequired }
UsersList.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(UsersList)
