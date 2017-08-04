import React from 'react'
import { shape, number, string, func } from 'prop-types'
import { Table } from 'semantic-ui-react'

import { dataSourceQueueStatuses } from 'helpers/enums'
import { formatDateTime } from 'helpers/dateHelper'
import styles from './styles.pcss'

const DataSourceQueueItem = ({ data, localize }) => (
  <Table.Row>
    <Table.Cell className={styles.wrap}>
      {data.fileName}
    </Table.Cell>
    <Table.Cell className={styles.wrap}>
      {data.dataSourceTemplateName}
    </Table.Cell>
    <Table.Cell className={styles.wrap}>
      {formatDateTime(data.uploadDateTime)}
    </Table.Cell>
    <Table.Cell className={styles.wrap}>
      {data.userName}
    </Table.Cell>
    <Table.Cell className={styles.wrap}>
      {localize(dataSourceQueueStatuses.get(data.status))}
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
