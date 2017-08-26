import React from 'react'
import { number, string, func, bool } from 'prop-types'
import { Table, Button } from 'semantic-ui-react'
import { Link } from 'react-router'

const ListItem = (
  { id, name, description, priority, allowedOperations, canEdit, canDelete, onDelete },
) => (
  <Table.Row>
    <Table.Cell content={id} className="wrap-content" />
    <Table.Cell className="wrap-content">
      {canEdit
        ? <Link to={`/datasources/edit/${id}`}>{name}</Link>
        : name}
    </Table.Cell>
    <Table.Cell content={description} className="wrap-content" />
    <Table.Cell content={priority} className="wrap-content" />
    <Table.Cell content={allowedOperations} className="wrap-content" />
    {canDelete &&
      <Table.Cell className="wrap-content">
        <Button onClick={onDelete} icon="remove" color="red" />
      </Table.Cell>}
  </Table.Row>
)

ListItem.propTypes = {
  id: number.isRequired,
  name: string.isRequired,
  description: string,
  priority: number.isRequired,
  allowedOperations: number.isRequired,
  canEdit: bool,
  canDelete: bool,
  onDelete: func,
}

ListItem.defaultProps = {
  description: '',
  canEdit: false,
  canDelete: false,
  onDelete: () => { },
}

export default ListItem
