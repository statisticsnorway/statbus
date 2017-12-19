import React from 'react'
import { Link } from 'react-router'
import { shape, number, string, func, array } from 'prop-types'
import { Table, Button } from 'semantic-ui-react'

const LogItem = ({ data, localize }) => (
  <Table.Row>
    <Table.Cell className="wrap-content">{data.unitName}</Table.Cell>
    <Table.Cell className="wrap-content">{localize(data.unitType)}</Table.Cell>
    <Table.Cell className="wrap-content">{data.summaryMessages.map(x => localize(x)).join(', ')}</Table.Cell>
    <Table.Cell className="wrap-content">
      <Button
        as={Link}
        to={`analysisqueue/${data.id}`}
        content={localize('View')}
        icon="search"
        primary
        disabled
      />
    </Table.Cell>
  </Table.Row>
)
LogItem.propTypes = {
  data: shape({
    id: number.isRequired,
    unitName: string.isRequired,
    unitType: string.isRequired,
    summaryMessages: array.isRequired,
  }).isRequired,
  localize: func.isRequired,
}

export default LogItem
