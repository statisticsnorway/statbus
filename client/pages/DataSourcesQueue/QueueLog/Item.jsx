import React from 'react'
import { shape, number, string, func, oneOfType } from 'prop-types'
import { Link } from 'react-router'
import { Table, Button } from 'semantic-ui-react'

import { formatDateTime } from 'helpers/dateHelper'
import { dataSourceQueueLogStatuses as statuses } from 'helpers/enums'

const LogItem = ({ data, localize }) => (
  <Table.Row>
    <Table.Cell content={data.id} width={1} />
    <Table.Cell content={data.name} width={3} className="wrap-content" />
    <Table.Cell content={formatDateTime(data.started)} width={2} />
    <Table.Cell content={data.ended && formatDateTime(data.ended)} width={2} />
    <Table.Cell content={data.statId} width={1} />
    <Table.Cell content={localize(statuses.get(data.status))} width={1} />
    <Table.Cell content={localize(data.note)} width={5} className="wrap-content" />
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
}

export default LogItem
