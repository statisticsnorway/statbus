import React from 'react'
import { string, bool, func } from 'prop-types'
import { Confirm } from 'semantic-ui-react'

const Notification = ({ title, body, open, onConfirm, onCancel, hideNotification, localize }) => (
  <Confirm
    open={open}
    cancelButton={localize('No')}
    confirmButton={localize('Yes')}
    header={title === undefined ? title : localize(title)}
    content={localize(body)}
    onCancel={() => {
      hideNotification()
      onCancel()
    }}
    onConfirm={() => {
      hideNotification()
      onConfirm()
    }}
  />
)

Notification.propTypes = {
  body: string.isRequired,
  open: bool.isRequired,
  localize: func.isRequired,
  title: string,
  onConfirm: func.isRequired,
  onCancel: func.isRequired,
  hideNotification: func.isRequired,
}

Notification.defaultProps = {
  title: undefined,
}

export default Notification
