import React, { useState } from 'react'
import { func, string, number } from 'prop-types'
import { Button, Confirm } from 'semantic-ui-react'
import { checkSystemFunction as sF } from '/helpers/config'

const ColumnActions = ({ localize, setUserStatus, getFilter, id, status, name }) => {
  const [confirmShow, setConfirmShow] = useState(false)

  const showConfirm = () => {
    setConfirmShow(true)
  }

  const handleCancel = () => {
    setConfirmShow(false)
  }

  const handleConfirm = () => {
    setUserStatus(id, getFilter(), status === 2)
    setConfirmShow(false)
  }

  const msgKey = status === 2 ? 'DeleteUserMessage' : 'UndeleteUserMessage'

  return (
    status !== 0 && (
      <Button.Group size="mini">
        {sF('UserDelete') && (
          <Button
            icon={status === 2 ? 'trash' : 'undo'}
            color={status === 2 ? 'red' : 'green'}
            onClick={showConfirm}
          />
        )}
        <Confirm
          open={confirmShow}
          onCancel={handleCancel}
          onConfirm={handleConfirm}
          content={`${localize(msgKey)} '${name}'?`}
          header={`${localize('AreYouSure')}`}
          confirmButton={localize('Ok')}
          cancelButton={localize('ButtonCancel')}
        />
      </Button.Group>
    )
  )
}

ColumnActions.propTypes = {
  localize: func.isRequired,
  setUserStatus: func.isRequired,
  getFilter: func.isRequired,
  id: string.isRequired,
  status: number.isRequired,
  name: string.isRequired,
}

export default ColumnActions
