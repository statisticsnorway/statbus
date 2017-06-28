import React from 'react'
import PropTypes from 'prop-types'
import { Table } from 'semantic-ui-react'

const TableHeader = ({ localize }) => (
  <Table.Header>
    <Table.Row>
      <Table.HeaderCell>{localize('RoleName')}</Table.HeaderCell>
      <Table.HeaderCell>{localize('Description')}</Table.HeaderCell>
      <Table.HeaderCell>{localize('ActiveUsers')}</Table.HeaderCell>
      <Table.HeaderCell />
    </Table.Row>
  </Table.Header>
)

TableHeader.propTypes = { localize: PropTypes.func.isRequired }

export default TableHeader
