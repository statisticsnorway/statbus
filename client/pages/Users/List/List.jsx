import React from 'react'
import { Link } from 'react-router'
import { Button, Loader, Message, List } from 'semantic-ui-react'
import styles from './styles'

const Item = ({ id, deleteUser, ...user }) => {
  const handleDelete = () => {
    if (confirm(`Delete user '${user.name}'. Are you sure?`)) deleteUser(id)
  }
  return (
    <List.Item>
      <List.Icon name="user" size="large" verticalAlign="middle" />
      <List.Content>
        <List.Header content={<Link to={`/users/edit/${id}`}>{user.name}</Link>} />
        <List.Description>
          <span>{user.description}</span>
          <Button onClick={handleDelete} negative>delete</Button>
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
    const { users, totalCount, totalPages, deleteUser, message, status } = this.props
    return (
      <div>
        <h2>Users list</h2>
        <div className={styles['list-root']}>
          <Link to="/users/create">Create</Link>
          <Loader active={status === 1} />
          <List>
            {users && users.map(u =>
              <Item key={u.id} {...u} deleteUser={deleteUser} />)}
          </List>
          {message && <Message content={message} />}
          <span>total: {totalCount}</span>
          <span>total pages: {totalPages}</span>
        </div>
      </div>
    )
  }
}
