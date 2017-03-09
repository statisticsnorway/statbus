import React from 'react'
import { Table } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'

const TableHeader = ({ localize, sortProperties }) => (
  <Table.Header>
    <Table.Row>
      <Table.HeaderCell>{localize('UserName')} {sortProperties.id === 'name' && <span>test</span>}{sortProperties.id}</Table.HeaderCell>
      <Table.HeaderCell>{localize('Description')}</Table.HeaderCell>
      <Table.HeaderCell>[regionName]</Table.HeaderCell>
      <Table.HeaderCell>[Roles]</Table.HeaderCell>
      <Table.HeaderCell>[creationDate] / </Table.HeaderCell>
      <Table.HeaderCell>[status]</Table.HeaderCell>
      <Table.HeaderCell />
    </Table.Row>
  </Table.Header>
)

TableHeader.propTypes = {
  localize: React.PropTypes.func.isRequired,
  sortProperties: React.PropTypes.shape({
    id: React.PropTypes.string.isRequired,
    sortAscending: React.PropTypes.bool.isRequired,
  }).isRequired,
}

export default wrapper(TableHeader)
