import React from 'react'
import { Message, Icon } from 'semantic-ui-react'

const ErrorMessage = ({ message }) => (
  <Message size="mini" icon negative>
    <Icon name="minus circle" />
    <Message.Header>{message}</Message.Header>
  </Message>
)

export default ErrorMessage
