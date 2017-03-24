import React from 'react'
import { Icon, Table } from 'semantic-ui-react'

const { shape, string, number, func, bool, oneOfType } = React.PropTypes

class ActivityView extends React.Component {
  static propTypes = {
    data: shape({
      id: number,
      activityRevx: oneOfType([string, number]),
      activityRevy: oneOfType([string, number]),
      activityYear: number,
      activityType: number,
      employees: number,
      turnover: number,
    }).isRequired,
    onEdit: func.isRequired,
    onDelete: func.isRequired,
    readonly: bool.isRequired,
  }

  editHandler = () => {
    const { data, onEdit } = this.props
    onEdit(data.id)
  }

  deleteHandler = () => {
    const { data, onDelete } = this.props
    onDelete(data.id)
  }

  render() {
    const { data, readonly } = this.props
    return (
      <Table.Row>
        <Table.Cell>{data.activityRevx}</Table.Cell>
        <Table.Cell>{data.activityRevy}</Table.Cell>
        <Table.Cell>{data.activityYear}</Table.Cell>
        <Table.Cell>{data.activityType}</Table.Cell>
        <Table.Cell>{data.employees}</Table.Cell>
        <Table.Cell>{data.turnover}</Table.Cell>
        <Table.Cell singleLine textAlign="right">
          {!readonly &&
            <span>
              <Icon name="edit" color="blue" onClick={this.editHandler} />
              <Icon name="trash" color="red" onClick={this.deleteHandler} />
            </span>
          }
        </Table.Cell>
      </Table.Row>
    )
  }
}

export default ActivityView
