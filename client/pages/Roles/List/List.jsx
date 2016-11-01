import React from 'react'
import { Link } from 'react-router'
import { Button, Loader, Message } from 'semantic-ui-react'
import styles from './styles'

const Item = ({ id, name, description, deleteHandler }) => {
  const handleDelete = () => {
    if (confirm('are you sure?')) deleteHandler(id)
  }
  return (
    <div>
      <div>
        <span>{name}</span>
        <span>{description}</span>
      </div>
      <div>
        <Link to={`/editrole/${id}`}>edit</Link>
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
    const { roles, status, message, deleteRole } = this.props
    return (
      <div className={styles['list-root']}>
        <Link to="/createrole">Create</Link>
        <Loader active={status === 1} />
        {roles && roles.length > 0
          && roles.map(r => <Item key={r.id} {...r} deleteHandler={deleteRole} />)}
        {message && <Message content={message} />}
      </div>
    )
  }
}
