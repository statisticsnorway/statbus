import React from 'react'
import { Input, Icon, Table, Select } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'
import activityTypes from './activityTypes'

const activities = [...activityTypes.entries()].map(([key, value]) => ({ key, value }))

const { shape, number, func } = React.PropTypes

class ActivityEdit extends React.Component {
  static propTypes = {
    data: shape({
      id: number,
      activityRevx: number,
      activityRevy: number,
      activityYear: number,
      activityType: number,
      employees: number,
      turnover: number,
    }).isRequired,
    onSave: func.isRequired,
    onCancel: func.isRequired,
    localize: func.isRequired,
  }

  state = {
    activityRevx: 0,
    activityRevy: 0,
    activityYear: 2017,
    activityType: 1,
    employees: 0,
    turnover: 0,
    ...this.props.data,
  }

  onFieldChange = (e, { name, value }) => {
    this.setState({
      [name]: value,
    })
  }

  saveHandler = () => {
    const { onSave } = this.props
    onSave(this.state)
  }

  cancelHandler = () => {
    const { onCancel } = this.props
    onCancel(this.state.id)
  }

  render() {
    const data = this.state
    const { localize } = this.props
    return (
      <Table.Row>
        <Table.Cell>
          <Input name="activityRevx" defaultValue={data.activityRevx} onChange={this.onFieldChange} />
        </Table.Cell>
        <Table.Cell>
          <Input name="activityRevy" defaultValue={data.activityRevy} onChange={this.onFieldChange} />
        </Table.Cell>
        <Table.Cell>
          <Input name="activityYear" defaultValue={data.activityYear} onChange={this.onFieldChange} />
        </Table.Cell>
        <Table.Cell>
          <Select
            value={data.activityType}
            options={activities.map(({ key, value }) => ({ value: key, text: localize(value) }))}
            name="activityType"
            onChange={this.onFieldChange}
            size="mini"
          />
        </Table.Cell>
        <Table.Cell>
          <Input name="employees" type="number" defaultValue={data.employees} onChange={this.onFieldChange} />
        </Table.Cell>
        <Table.Cell>
          <Input name="turnover" type="number" defaultValue={data.turnover} onChange={this.onFieldChange} />
        </Table.Cell>
        <Table.Cell singleLine>
          <Icon name="check" color="green" onClick={this.saveHandler} />
          <Icon name="cancel" color="red" onClick={this.cancelHandler} />
        </Table.Cell>
      </Table.Row>
    )
  }
}

export default wrapper(ActivityEdit)

