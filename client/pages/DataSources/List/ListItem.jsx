import React from 'react'
import { number, string } from 'prop-types'
import { Table } from 'semantic-ui-react'

const ListItem = (
  { id, name, description, priority, allowedOperations },
) => (
  <Table.Row>
    <Table.Cell className="wrap-content">
      {id}
    </Table.Cell>
    <Table.Cell className="wrap-content">
      {name}
    </Table.Cell>
    <Table.Cell className="wrap-content">
      {description}
    </Table.Cell>
    <Table.Cell className="wrap-content">
      {priority}
    </Table.Cell>
    <Table.Cell className="wrap-content">
      {allowedOperations}
    </Table.Cell>
  </Table.Row>
)

ListItem.propTypes = {
  id: number.isRequired,
  name: string.isRequired,
  description: string,
  priority: number.isRequired,
  allowedOperations: number.isRequired,
}

ListItem.defaultProps = {
  description: '',
}

export default ListItem
