import React from 'react'
import { func, string, number } from 'prop-types'
import { Link } from 'react-router'
import { Table, Label } from 'semantic-ui-react'

import { checkSystemFunction as sF } from '/helpers/config'
import styles from './styles.scss'

const ListItem = ({ id, name, description, activeUsers, status, localize }) => (
  <Table.Body>
    <Table.Row className={styles.wrap}>
      <Table.Cell>
        {sF('RoleEdit') ? (
          <Link to={`/roles/edit/${id}`}>{localize(name)}</Link>
        ) : (
          <span>{name}</span>
        )}
      </Table.Cell>
      <Table.Cell>{description}</Table.Cell>
      <Table.Cell>
        <Label circular color={activeUsers === 0 && status ? 'red' : 'teal'}>
          {activeUsers}
        </Label>
      </Table.Cell>
    </Table.Row>
  </Table.Body>
)

ListItem.propTypes = {
  onToggle: func.isRequired,
  id: string.isRequired,
  name: string.isRequired,
  description: string.isRequired,
  activeUsers: number.isRequired,
  status: number.isRequired,
  localize: func.isRequired,
}

export default ListItem
