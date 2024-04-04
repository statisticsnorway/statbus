import React from 'react'
import { shape, number, func } from 'prop-types'
import { Table } from 'semantic-ui-react'
import { activityTypes } from '/helpers/enums'

const TableItem = ({ data, localize }) => (
  <Table.Row>
    <Table.Cell className="wrap-content">{data.id}</Table.Cell>
    <Table.Cell className="wrap-content">
      {localize(activityTypes.get(data.activityType))}
    </Table.Cell>
    <Table.Cell className="wrap-content">{data.activityYear}</Table.Cell>
    <Table.Cell className="wrap-content">{data.employees}</Table.Cell>
    <Table.Cell className="wrap-content">{data.turnover}</Table.Cell>
  </Table.Row>
)

TableItem.propTypes = {
  data: shape({
    id: number.isRequired,
    activityType: number.isRequired,
    activityYear: number.isRequired,
    employees: number.isRequired,
    turnover: number.isRequired,
  }).isRequired,
  localize: func.isRequired,
}

export default TableItem
