import React from 'react'
import { Link } from 'react-router'
import { Loader, Message } from 'semantic-ui-react'
import styles from './styles'
// TODO: add edit link
const Item = ({ id, name, description }) => (
  <div>
    <div>
      <span>{id}</span>
      <span>{name}</span>
      <span>{description}</span>
    </div>
    <div>
      <button>edit</button>
      <button>remove</button>
    </div>
  </div>
)

export default class List extends React.Component {
  componentDidMount() {
    this.props.fetchRoles()
  }
  render() {
    const { roles, status, message } = this.props
    return (
      <div className={styles['list-root']}>
        <Link to="createrole">Create</Link>
        <Loader active={status === 1} />
        {roles.length > 0
          && roles.map(r => <Item key={r.id} {...r} />)}
        {message && <Message content={message} />}
      </div>
    )
  }
}
