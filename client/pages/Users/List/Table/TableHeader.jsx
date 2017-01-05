import React from 'react'
import { Table } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'

const TableHeader = ({ localize }) => (
  <Table.Header>
    <Table.Row>
      <Table.HeaderCell>{localize('UserName')}</Table.HeaderCell>
      <Table.HeaderCell>{localize('Description')}</Table.HeaderCell>
      <Table.HeaderCell />
    </Table.Row>
  </Table.Header>
)

TableHeader.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(TableHeader)
