import React from 'react'
import { Link } from 'react-router'
import { shape, number, string, func } from 'prop-types'
import { Table, Button } from 'semantic-ui-react'

import { dataSourceQueueStatuses } from 'helpers/enums'
import { formatDateTime } from 'helpers/dateHelper'

const DataSourceQueueItem = ({ data, localize }) => (
  <Table.Row>
    <Table.Cell className="wrap-content">{data.fileName}</Table.Cell>
    <Table.Cell className="wrap-content">{data.dataSourceTemplateName}</Table.Cell>
    <Table.Cell className="wrap-content">{formatDateTime(data.uploadDateTime)}</Table.Cell>
    <Table.Cell className="wrap-content">{data.userName}</Table.Cell>
    <Table.Cell className="wrap-content">
      {localize(dataSourceQueueStatuses.get(data.status))}
    </Table.Cell>
    <Table.Cell className="wrap-content">
      <Button
        as={Link}
        to={`datasourcesqueue/${data.id}/log`}
        content={localize('Logs')}
        icon="search"
        primary
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
  }).isRequired,
  localize: func.isRequired,
}

export default DataSourceQueueItem
