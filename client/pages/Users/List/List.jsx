import React from 'react'
import { Link } from 'react-router'
import { Button, Loader, List } from 'semantic-ui-react'

import { systemFunction as sF } from '../../../helpers/checkPermissions'
import styles from './styles'

const Item = ({ id, deleteUser, ...user }) => {
  const handleDelete = () => {
    if (confirm(`Delete user '${user.name}'. Are you sure?`)) deleteUser(id)
  }
  return (
    <List.Item>
      <List.Icon name="user" size="large" verticalAlign="middle" />
      <List.Content>
        <List.Header
          content={sF('UserEdit')
            ? <Link to={`/users/edit/${id}`}>{user.name}</Link>
            : <span>{user.name}</span>}
        />
        <List.Description>
          <span>{user.description}</span>
          {sF('UserDelete') && <Button onClick={handleDelete} negative>delete</Button>}
        </List.Description>
      </List.Content>
    </List.Item>
  )
}

export default class UsersList extends React.Component {
  componentDidMount() {
    this.props.fetchUsers()
  }
  render() {
    const { users, totalCount, totalPages, deleteUser, status } = this.props
    return (
      <div>
        <h2>Users list</h2>
        <div className={styles['list-root']}>
          {sF('UserCreate') && <Link to="/users/create">Create</Link>}
          <Loader active={status === 1} />
          <List>
            {users && users.map(u =>
              <Item key={u.id} {...u} deleteUser={deleteUser} />)}
          </List>
          <span>total: {totalCount}</span>
          <span>total pages: {totalPages}</span>
        </div>
      </div>
    )
  }
}
