import React from 'react'
import { shape, number, string, func } from 'prop-types'
import { Link } from 'react-router'
import { Table, Button } from 'semantic-ui-react'

import { formatDateTime } from 'helpers/dateHelper'
import { dataSourceQueueLogStatuses as statuses } from 'helpers/enums'

const LogItem = ({ data, localize }) => (
  <Table.Row>
    <Table.Cell className="wrap-content">
      {data.id}
    </Table.Cell>
    <Table.Cell className="wrap-content">
      {data.name}
    </Table.Cell>
    <Table.Cell className="wrap-content">
      {formatDateTime(data.started)}
    </Table.Cell>
    <Table.Cell className="wrap-content">
      {data.ended && formatDateTime(data.ended)}
    </Table.Cell>
    <Table.Cell className="wrap-content">
      {data.statId}
    </Table.Cell>
    <Table.Cell className="wrap-content">
      {localize(statuses.get(data.status))}
    </Table.Cell>
    <Table.Cell className="wrap-content">
      {data.note}
    </Table.Cell>
    <Table.Cell className="wrap-content">
      <Button
        as={Link}
        to={`${window.location.pathname}/${data.id}`}
        content={localize('Revise')}
        icon="pencil"
        primary
      />
    </Table.Cell>
  </Table.Row>
)

LogItem.propTypes = {
  data: shape({
    id: number.isRequired,
    name: string.isRequired,
    started: string.isRequired,
    ended: string,
    statId: number,
    status: number.isRequired,
    note: string,
  }).isRequired,
  localize: func.isRequired,
}

export default LogItem
