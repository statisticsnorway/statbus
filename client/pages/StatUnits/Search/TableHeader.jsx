import React from 'react'
import PropTypes from 'prop-types'
import { Table } from 'semantic-ui-react'

const TableHeader = ({ localize }) => (
  <Table.Header>
    <Table.Row>
      <Table.HeaderCell>{localize('StatId')}</Table.HeaderCell>
      <Table.HeaderCell>{localize('Name')}</Table.HeaderCell>
      <Table.HeaderCell>{localize('Region')}</Table.HeaderCell>
      <Table.HeaderCell>{localize('AddressPart1')}</Table.HeaderCell>
      <Table.HeaderCell>{localize('AddressPart2')}</Table.HeaderCell>
      <Table.HeaderCell>{localize('AddressPart3')}</Table.HeaderCell>
      <Table.HeaderCell>{localize('LegalForm')}</Table.HeaderCell>
      <Table.HeaderCell>{localize('ContactPerson')}</Table.HeaderCell>
      <Table.HeaderCell>{localize('PrimaryActivity')}</Table.HeaderCell>
      <Table.HeaderCell>{localize('TaxRegId')}</Table.HeaderCell>
      <Table.HeaderCell />
    </Table.Row>
  </Table.Header>
)

TableHeader.propTypes = { localize: PropTypes.func.isRequired }

export default TableHeader
