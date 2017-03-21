import React from 'react'
import { Button, Icon, Loader, Table } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'

const { shape, number, func } = React.PropTypes

class ActivitiesList extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    data: shape({
      id: number,
      turnover: number.isRequired,
      employees: number.isRequired,
    }).isRequired,
  }

  renderRows() {
    const { data } = this.props
    return (
      data.map(v => (
        <Table.Row key={v.id}>
          <Table.Cell>{v.activityRevx}</Table.Cell>
          <Table.Cell>{v.activityRevy}</Table.Cell>
          <Table.Cell>{v.activityYear}</Table.Cell>
          <Table.Cell>{v.activityType}</Table.Cell>
          <Table.Cell>{v.employees}</Table.Cell>
          <Table.Cell>{v.turnover}</Table.Cell>
        </Table.Row>
      ))
    )
  }

  render() {
    const { localize } = this.props
    return (
      <Table size="small">
        <Table.Header>
          <Table.Row>
            <Table.HeaderCell>{localize('StatUnitActivityRevX')}</Table.HeaderCell>
            <Table.HeaderCell>{localize('StatUnitActivityRevY')}</Table.HeaderCell>
            <Table.HeaderCell>{localize('StatUnitActivityYear')}</Table.HeaderCell>
            <Table.HeaderCell>{localize('StatUnitActivityType')}</Table.HeaderCell>
            <Table.HeaderCell>{localize('StatUnitActivityEmployeesNumber')}</Table.HeaderCell>
            <Table.HeaderCell>{localize('Turnover')}</Table.HeaderCell>
          </Table.Row>
        </Table.Header>
        <Table.Body>
          {this.renderRows()}
        </Table.Body>
      </Table>
    )
  }
}

export default wrapper(ActivitiesList)
