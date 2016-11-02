import React from 'react'
import { Link } from 'react-router'
import { Button, Loader, Message } from 'semantic-ui-react'
import styles from './styles'

const Item = ({ id, deleteUser, ...user }) => {
  const handleDelete = () => {
    if (confirm(`Delete user '${user.name}'. Are you sure?`)) deleteUser(id)
  }
  return (
    <div>
      <span>name: {user.name}</span>
      <span>login: {user.login}</span>
      <span>description: {user.description}</span>
      <Link to={`/users/edit/${id}`}>edit</Link>
      <Button onClick={handleDelete} negative>delete</Button>
    </div>
  )
}

export default class List extends React.Component {
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
          {users && users.map(u =>
            <Item key={u.id} {...u} deleteUser={deleteUser} />)}
          {message && <Message content={message} />}
          <span>total: {totalCount}</span>
          <span>total pages: {totalPages}</span>
        </div>
      </div>
    )
  }
}
