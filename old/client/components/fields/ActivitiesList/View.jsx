import React from 'react'
import { shape, string, number, func, bool, oneOfType } from 'prop-types'
import { Icon, Table, Popup, Confirm } from 'semantic-ui-react'

import { activityTypes } from '/helpers/enums'
import { getNewName } from '/helpers/locale'

class ActivityView extends React.Component {
  static propTypes = {
    value: shape({
      id: number,
      activityYear: oneOfType([string, number]),
      activityType: oneOfType([string, number]),
      employees: oneOfType([string, number]),
      turnover: oneOfType([string, number]),
      activityCategoryId: oneOfType([string, number]),
    }).isRequired,
    onEdit: func.isRequired,
    onDelete: func.isRequired,
    readOnly: bool.isRequired,
    editMode: bool.isRequired,
    localize: func.isRequired,
    index: number,
  }

  state = {
    showConfirm: false,
  }

  editHandler = () => {
    const { value, onEdit } = this.props
    onEdit(this.props.index)
  }

  deleteHandler = () => {
    this.setState({ showConfirm: true })
  }

  cancelHandler = () => {
    this.setState({ showConfirm: false })
  }

  confirmHandler = () => {
    this.setState({ showConfirm: false })
    const { value, onDelete } = this.props
    onDelete(this.props.index)
  }

  render() {
    const { value, readOnly, editMode, localize } = this.props
    const { showConfirm } = this.state
    return (
      <Table.Row>
        <Table.Cell>{value.activityCategory && value.activityCategory.code}</Table.Cell>
        <Table.Cell>
          {value.activityCategory && getNewName(value.activityCategory, false)}
        </Table.Cell>
        <Table.Cell>{localize(activityTypes.get(value.activityType))}</Table.Cell>
        <Table.Cell textAlign="center">{value.employees}</Table.Cell>
        <Table.Cell textAlign="center">{value.turnover}</Table.Cell>
        <Table.Cell textAlign="center">
          {value.activityYear === 0 ? '' : value.activityYear}
        </Table.Cell>
        {!readOnly && (
          <Table.Cell singleLine textAlign="right">
            {!editMode && (
              <span>
                <Popup
                  trigger={<Icon name="edit" color="blue" onClick={this.editHandler} />}
                  content={localize('EditButton')}
                  position="top center"
                  size="mini"
                />
                <Popup
                  trigger={<Icon name="trash" color="red" onClick={this.deleteHandler} />}
                  content={localize('ButtonDelete')}
                  position="top center"
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
            )}
          </Table.Cell>
        )}
      </Table.Row>
    )
  }
}

export default ActivityView
