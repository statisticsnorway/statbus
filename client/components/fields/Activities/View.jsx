import React from 'react'
import { Icon, Table, Popup, Confirm } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'
import { formatDate } from 'helpers/dateHelper'
import activityTypes from './activityTypes'

const { shape, string, number, func, bool, oneOfType } = React.PropTypes

class ActivityView extends React.Component {
  static propTypes = {
    data: shape({
      id: number,
      activityRevy: oneOfType([string, number]),
      activityYear: oneOfType([string, number]),
      activityType: oneOfType([string, number]),
      employees: oneOfType([string, number]),
      turnover: oneOfType([string, number]),
      activityRevxCategory: shape({
        code: string.isRequired,
        name: string.isRequired,
      }),
    }).isRequired,
    onEdit: func.isRequired,
    onDelete: func.isRequired,
    readOnly: bool.isRequired,
    editMode: bool.isRequired,
    localize: func.isRequired,
  }

  state = {
    showConfirm: false,
  }

  editHandler = () => {
    const { data, onEdit } = this.props
    onEdit(data.id)
  }

  deleteHandler = () => {
    this.setState({ showConfirm: true })
  }

  cancelHandler = () => {
    this.setState({ showConfirm: false })
  }

  confirmHandler = () => {
    this.setState({ showConfirm: false })
    const { data, onDelete } = this.props
    onDelete(data.id)
  }

  render() {
    const { data, readOnly, editMode, localize } = this.props
    const { showConfirm } = this.state
    return (
      <Table.Row>
        <Table.Cell>{data.activityRevxCategory.code}</Table.Cell>
        <Table.Cell>{data.activityRevxCategory.name}</Table.Cell>
        <Table.Cell>{localize(activityTypes.get(data.activityType))}</Table.Cell>
        <Table.Cell textAlign="right">{data.employees}</Table.Cell>
        <Table.Cell textAlign="right">{data.turnover}</Table.Cell>
        <Table.Cell textAlign="center">{data.activityYear}</Table.Cell>
        <Table.Cell textAlign="center">{formatDate(data.idDate)}</Table.Cell>
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
                <Confirm
                  open={showConfirm}
                  cancelButton={localize('No')}
                  confirmButton={localize('Yes')}
                  header={localize('DialogTitleDelete')}
                  content={localize('DialogBodyDelete')}
                  onCancel={this.cancelHandler}
                  onConfirm={this.confirmHandler}
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
