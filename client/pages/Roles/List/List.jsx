import React from 'react'
import { Link } from 'react-router'
import { Button, Loader, Message } from 'semantic-ui-react'
import styles from './styles'

const Item = ({ id, name, description, deleteRole }) => {
  const handleDelete = () => {
    if (confirm(`Delete role '${name}'. Are you sure?`)) deleteRole(id)
  }
  return (
    <div>
      <div>
        <span>{name}</span>
        <span>{description}</span>
      </div>
      <div>
        <Link to={`/roles/edit/${id}`}>edit</Link>
        <Button onClick={handleDelete} negative>delete</Button>
      </div>
    </div>
  )
}

export default class List extends React.Component {
  componentDidMount() {
    this.props.fetchRoles()
  }
  render() {
    const { roles, totalCount, totalPages, status, message, deleteRole } = this.props
    return (
      <div className={styles['list-root']}>
        <Link to="/roles/create">Create</Link>
        <Loader active={status === 1} />
        {roles && roles.map(r =>
          <Item key={r.id} {...r} deleteRole={deleteRole} />)}
        {message && <Message content={message} />}
        <span>total: {totalCount}</span>
        <span>total pages: {totalPages}</span>
      </div>
    )
  }
}
