import React from 'react'
import { shape, number, string, func, oneOfType } from 'prop-types'
import { Link } from 'react-router'
import { Table, Button } from 'semantic-ui-react'

import { formatDateTime } from '/helpers/dateHelper'
import { dataSourceQueueLogStatuses as statuses } from '/helpers/enums'

const LogItem = ({ data, localize, deleteLog }) => (
  <Table.Row>
    <Table.Cell content={data.statId} width={1} />
    <Table.Cell content={data.name} width={3} className="wrap-content" />
    <Table.Cell content={formatDateTime(data.started)} width={2} />
    <Table.Cell content={data.ended && formatDateTime(data.ended)} width={2} />
    <Table.Cell content={localize(statuses.get(data.status))} width={1} />
    <Table.Cell
      content={data.note.split(',').map(x => `${localize(x)}. `)}
      width={5}
      className="wrap-content"
    />
    <Table.Cell width={1}>
      {data.status !== 1 && (
        <Button
          as={Link}
          to={`${window.location.pathname}/${data.id}`}
          content={localize('Revise')}
          icon="pencil"
          primary
        />
      )}
      {data.id === 0 && (
        <Button
          as={Link}
          to={`${window.location.pathname}/activity/${data.statId}`}
          content={localize('Revise')}
          icon="pencil"
          primary
        />
      )}
    </Table.Cell>
    <Table.Cell width={1}>
      <Button
        onClick={() => deleteLog(data.id)}
        content={localize('Reject')}
        icon="trash"
        negative
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
    statId: oneOfType([string, number]),
    status: number.isRequired,
    note: string,
  }).isRequired,
  localize: func.isRequired,
  deleteLog: func.isRequired,
}

export default LogItem
