import React from 'react'
import { Link } from 'react-router'
import { shape, number, string, func } from 'prop-types'
import { Table, Button } from 'semantic-ui-react'

import { formatDateTime } from '/helpers/dateHelper'

const AnalysisQueueItem = ({ data, localize, deleteQueue }) => {
  const formatDate = x => (x === null ? localize('NoValue') : formatDateTime(x))
  return (
    <Table.Row>
      <Table.Cell className="wrap-content">{formatDateTime(data.userStartPeriod)}</Table.Cell>
      <Table.Cell className="wrap-content">{formatDateTime(data.userEndPeriod)}</Table.Cell>
      <Table.Cell className="wrap-content">{formatDate(data.serverStartPeriod)}</Table.Cell>
      <Table.Cell className="wrap-content">{formatDate(data.serverEndPeriod)}</Table.Cell>
      <Table.Cell className="wrap-content">{data.userName}</Table.Cell>
      <Table.Cell className="wrap-content">{data.comment}</Table.Cell>
      <Table.Cell className="wrap-content">
        <Button
          as={Link}
          to={`analysisqueue/${data.id}/log`}
          content={localize('Logs')}
          icon="search"
          primary
        />
      </Table.Cell>
      <Table.Cell className="wrap-content">
        <Button
          onClick={() => deleteQueue(data)}
          content={localize('Reject')}
          icon="trash"
          negative
        />
      </Table.Cell>
    </Table.Row>
  )
}

AnalysisQueueItem.propTypes = {
  data: shape({
    id: number.isRequired,
    comment: string,
    serverEndPeriod: string,
    serverStartPeriod: string,
    userEndPeriod: string.isRequired,
    userStartPeriod: string.isRequired,
    userName: string.isRequired,
  }).isRequired,
  localize: func.isRequired,
  deleteQueue: func.isRequired,
}

export default AnalysisQueueItem
