import React from 'react'
import { Input, Icon, Table } from 'semantic-ui-react'

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
    return (
      <Table.Row>
        <Table.Cell>
          <Input size="mini" name="activityRevx" defaultValue={data.activityRevx} onChange={this.onFieldChange} />
        </Table.Cell>
        <Table.Cell>
          <Input size="mini" name="activityRevy" defaultValue={data.activityRevy} onChange={this.onFieldChange} />
        </Table.Cell>
        <Table.Cell>
          <Input size="mini" name="activityYear" defaultValue={data.activityYear} onChange={this.onFieldChange} />
        </Table.Cell>
        <Table.Cell>
          <Input size="mini" name="activityType" defaultValue={data.activityType} onChange={this.onFieldChange} />
        </Table.Cell>
        <Table.Cell>
          <Input size="mini" name="employees" defaultValue={data.employees} onChange={this.onFieldChange} />
        </Table.Cell>
        <Table.Cell>
          <Input size="mini" name="turnover" defaultValue={data.turnover} onChange={this.onFieldChange} />
        </Table.Cell>
        <Table.Cell singleLine>
          <Icon name="check" color="green" onClick={this.saveHandler} />
          <Icon name="cancel" color="red" onClick={this.cancelHandler} />
        </Table.Cell>
      </Table.Row>
    )
  }
}

export default ActivityEdit

