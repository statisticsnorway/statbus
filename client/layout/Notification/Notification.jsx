import React from 'react'
import { Confirm } from 'semantic-ui-react'
import { wrapper } from 'helpers/locale'

const Notification = ({ title, body, open, onConfirm, onCancel, hideNotification, localize }) => (
  <Confirm
    open={open}
    cancelButton={localize('No')}
    confirmButton={localize('Yes')}
    header={title === undefined ? title : localize(title)}
    content={localize(body)}
    onCancel={() => { hideNotification(); onCancel() }}
    onConfirm={() => { hideNotification(); onConfirm() }}
  />
)

const { string, bool, func } = React.PropTypes

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

export default wrapper(Notification)
