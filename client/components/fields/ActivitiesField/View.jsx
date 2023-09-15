import React, { useState } from 'react'
import PropTypes from 'prop-types'
import { Icon, Table, Popup, Confirm } from 'semantic-ui-react'

import { activityTypes } from 'helpers/enums'
import { getNewName } from 'helpers/locale'

function ActivityView(props) {
  const { value, onEdit, onDelete, readOnly, editMode, localize, index } = props

  const [showConfirm, setShowConfirm] = useState(false)

  const editHandler = () => {
    onEdit(index)
  }

  const deleteHandler = () => {
    setShowConfirm(true)
  }

  const cancelHandler = () => {
    setShowConfirm(false)
  }

  const confirmHandler = () => {
    setShowConfirm(false)
    onDelete(index)
  }

  return (
    <Table.Row>
      <Table.Cell>{value.activityCategory && value.activityCategory.code}</Table.Cell>
      <Table.Cell>{value.activityCategory && getNewName(value.activityCategory, false)}</Table.Cell>
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
                trigger={<Icon name="edit" color="blue" onClick={editHandler} />}
                content={localize('EditButton')}
                position="top center"
                size="mini"
              />
              <Popup
                trigger={<Icon name="trash" color="red" onClick={deleteHandler} />}
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
                onCancel={cancelHandler}
                onConfirm={confirmHandler}
              />
            </span>
          )}
        </Table.Cell>
      )}
    </Table.Row>
  )
}

ActivityView.propTypes = {
  value: PropTypes.shape({
    id: PropTypes.number,
    activityYear: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
    activityType: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
    employees: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
    turnover: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
    activityCategoryId: PropTypes.oneOfType([PropTypes.string, PropTypes.number]),
  }).isRequired,
  onEdit: PropTypes.func.isRequired,
  onDelete: PropTypes.func.isRequired,
  readOnly: PropTypes.bool.isRequired,
  editMode: PropTypes.bool.isRequired,
  localize: PropTypes.func.isRequired,
  index: PropTypes.number,
}

export default ActivityView
