import React from 'react'
import { shape, number, string, func } from 'prop-types'
import { Table } from 'semantic-ui-react'

import statuses from 'helpers/dataSourceQueueLogStatuses'
import styles from './styles.pcss'

const LogItem = ({ data, localize }) => (
  <Table.Row>
    <Table.Cell className={styles.wrap}>
      {data.id}
    </Table.Cell>
    <Table.Cell className={styles.wrap}>
      {data.name}
    </Table.Cell>
    <Table.Cell className={styles.wrap}>
      {data.started}
    </Table.Cell>
    <Table.Cell className={styles.wrap}>
      {data.ended}
    </Table.Cell>
    <Table.Cell className={styles.wrap}>
      {data.statId}
    </Table.Cell>
    <Table.Cell className={styles.wrap}>
      {localize(statuses.get(data.status))}
    </Table.Cell>
    <Table.Cell className={styles.wrap}>
      {data.note}
    </Table.Cell>
  </Table.Row>
)

LogItem.propTypes = {
  data: shape({
    id: number.isRequired,
    name: string.isRequired,
    started: string.isRequired,
    ended: string,
    statId: number.isRequired,
    status: number.isRequired,
    note: string,
  }).isRequired,
  localize: func.isRequired,
}

export default LogItem
