import React from 'react'
import { Link } from 'react-router'
import { shape, number, string, func, bool } from 'prop-types'
import { Table, Button } from 'semantic-ui-react'

import { dataSourceQueueStatuses } from '/helpers/enums'
import { formatDateTime } from '/helpers/dateHelper'

const DataSourceQueueItem = ({ data, localize, deleteQueue, isLoading }) => (
  <Table.Row>
    <Table.Cell className="wrap-content">{data.fileName}</Table.Cell>
    <Table.Cell className="wrap-content">{data.dataSourceTemplateName}</Table.Cell>
    <Table.Cell className="wrap-content">{formatDateTime(data.uploadDateTime)}</Table.Cell>
    <Table.Cell className="wrap-content">{data.userName}</Table.Cell>
    <Table.Cell className="wrap-content">
      {localize(dataSourceQueueStatuses.get(data.status))}
    </Table.Cell>
    <Table.Cell className="wrap-content">{localize(data.note)}</Table.Cell>
    <Table.Cell className="wrap-content">
      {dataSourceQueueStatuses.get(data.status) !== 'DataLoadCompleted' &&
        dataSourceQueueStatuses.get(data.status) !== 'DataLoadCompletedFailed' && (
          <Button
            as={Link}
            to={`datasourcesqueue/${data.id}/log`}
            content={localize('Logs')}
            icon="search"
            disabled={
              dataSourceQueueStatuses.get(data.status) === 'InQueue' ||
              dataSourceQueueStatuses.get(data.status) === 'Loading'
            }
            primary
          />
        )}
    </Table.Cell>
    <Table.Cell className="wrap-content">
      <Button
        onClick={() => deleteQueue(data)}
        content={localize('Reject')}
        icon="trash"
        disabled={dataSourceQueueStatuses.get(data.status) === 'Loading' || isLoading}
        negative
      />
    </Table.Cell>
  </Table.Row>
)

DataSourceQueueItem.propTypes = {
  data: shape({
    id: number.isRequired,
    fileName: string.isRequired,
    dataSourceTemplateName: string.isRequired,
    uploadDateTime: string.isRequired,
    userName: string.isRequired,
    status: number.isRequired,
    note: string.isRequired,
  }).isRequired,
  localize: func.isRequired,
  deleteQueue: func.isRequired,
  isLoading: bool.isRequired,
}

export default DataSourceQueueItem
