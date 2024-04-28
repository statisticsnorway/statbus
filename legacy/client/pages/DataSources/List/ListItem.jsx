import React from 'react'
import { number, string, func, bool } from 'prop-types'
import { Table, Button } from 'semantic-ui-react'
import { Link } from 'react-router'
import * as R from 'ramda'

import { dataSourceOperations, dataSourcePriorities } from '/helpers/enums'

const ListItem = ({
  id,
  name,
  description,
  priority,
  allowedOperations,
  canEdit,
  canDelete,
  onDelete,
  localize,
}) => (
  <Table.Row>
    <Table.Cell className="wrap-content">
      {canEdit ? <Link to={`/datasources/edit/${id}`}>{name}</Link> : name}
    </Table.Cell>
    <Table.Cell content={description} className="wrap-content" />
    <Table.Cell content={localize(dataSourcePriorities.get(priority))} className="wrap-content" />
    <Table.Cell
      content={localize(dataSourceOperations.get(allowedOperations))}
      className="wrap-content"
    />
    {canDelete && (
      <Table.Cell className="wrap-content">
        <Button onClick={onDelete} icon="trash" size="mini" color="red" floated="right" />
      </Table.Cell>
    )}
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
  localize: func,
}

ListItem.defaultProps = {
  description: '',
  canEdit: false,
  canDelete: false,
  onDelete: R.identity,
}

export default ListItem
