import React from 'react'
import { Link } from 'react-router'
import { Button, Table, Label } from 'semantic-ui-react'

import { systemFunction as sF } from 'helpers/checkPermissions'

const ListItem = ({ id, name, description, activeUsers, onDelete }) => (
  <Table.Body>
    <Table.Row>
      <Table.Cell>
        {sF('RoleEdit')
          ? <Link to={`/roles/edit/${id}`}>{name}</Link>
          : <span>{name}</span>}
      </Table.Cell>
      <Table.Cell>{description}</Table.Cell>
      <Table.Cell>
        <Label circular color={activeUsers === 0 ? 'red' : 'teal'}>
          {activeUsers}
        </Label>
      </Table.Cell>
      <Table.Cell textAlign="right">
        <Button.Group size="mini">
          {sF('RoleDelete')
            && <Button onClick={onDelete} icon="delete" color="red" />}
        </Button.Group>
      </Table.Cell>
    </Table.Row>
  </Table.Body>
)

const { func, string, number } = React.PropTypes

ListItem.propTypes = {
  onDelete: func.isRequired,
  id: string.isRequired,
  name: string.isRequired,
  description: string.isRequired,
  activeUsers: number.isRequired,
}

export default ListItem
