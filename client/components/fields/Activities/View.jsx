import React from 'react'
import { Icon, Table, Popup } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'
import { formatDateTime } from 'helpers/dateHelper'
import activityTypes from './activityTypes'

const { shape, string, number, func, bool, oneOfType } = React.PropTypes

class ActivityView extends React.Component {
  static propTypes = {
    data: shape({
      id: number,
      activityRevx: oneOfType([string, number]),
      activityRevy: oneOfType([string, number]),
      activityYear: number,
      activityType: number,
      employees: oneOfType([string, number]),
      turnover: oneOfType([string, number]),
    }).isRequired,
    onEdit: func.isRequired,
    onDelete: func.isRequired,
    readOnly: bool.isRequired,
    editMode: bool.isRequired,
    localize: func.isRequired,
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
    const { data, readOnly, editMode, localize } = this.props
    return (
      <Table.Row>
        <Table.Cell>{data.activityRevx}</Table.Cell>
        <Table.Cell>[ACTIVITY REVX NAME]</Table.Cell>
        <Table.Cell>{localize(activityTypes.get(data.activityType))}</Table.Cell>
        <Table.Cell>{data.employees}</Table.Cell>
        <Table.Cell>{data.turnover}</Table.Cell>
        <Table.Cell>{data.activityYear}</Table.Cell>
        <Table.Cell>{formatDateTime(data.idDate)}</Table.Cell>
        {!readOnly &&
          <Table.Cell singleLine textAlign="right">
            {!editMode &&
              <span>
                <Popup
                  trigger={<Icon name="edit" color="blue" onClick={this.editHandler} />}
                  content={localize('EditButton')}
                  size="mini"
                />
                <Popup
                  trigger={<Icon name="trash" color="red" onClick={this.deleteHandler} />}
                  content={localize('ButtonDelete')}
                  size="mini"
                />
              </span>
            }
          </Table.Cell>
        }
      </Table.Row>
    )
  }
}

export default wrapper(ActivityView)
