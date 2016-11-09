import React from 'react'
import { Link } from 'react-router'
import { List } from 'semantic-ui-react'

export default ({ users }) => (
  <List>
    {users.map(u => (
      <List.Item>
        <List.Icon name="user" size="small" verticalAlign="middle" />
        <List.Content>
          <List.Header content={<Link to={`/users/edit/${u.id}`}>{u.name}</Link>} />
          <List.Description>
            <span>{u.description}</span>
          </List.Description>
        </List.Content>
      </List.Item>
    ))}
  </List>
)
