import React from 'react'
import { Link } from 'react-router'
import { Button, Table, Label } from 'semantic-ui-react'

import { systemFunction as sF } from 'helpers/checkPermissions'
import styles from './styles.pcss'

const ListItem = ({ id, name, description, activeUsers, status, onToggle }) => (
  <Table.Body>
    <Table.Row className={styles.wrap}>
      <Table.Cell>
        {sF('RoleEdit')
          ? <Link to={`/roles/edit/${id}`}>{name}</Link>
          : <span>{name}</span>}
      </Table.Cell>
      <Table.Cell>{description}</Table.Cell>
      <Table.Cell>
        <Label circular color={activeUsers === 0 && status ? 'red' : 'teal'}>
          {activeUsers}
        </Label>
      </Table.Cell>
      <Table.Cell textAlign="right">
        <Button.Group size="mini">
          {sF('RoleDelete')
            && <Button onClick={onToggle} icon={status ? 'trash' : 'undo'} color={status ? 'red' : 'green'} />}
        </Button.Group>
      </Table.Cell>
    </Table.Row>
  </Table.Body>
)

const { func, string, number } = React.PropTypes

ListItem.propTypes = {
  onToggle: func.isRequired,
  id: string.isRequired,
  name: string.isRequired,
  description: string.isRequired,
  activeUsers: number.isRequired,
  status: number.isRequired,
}

export default ListItem
