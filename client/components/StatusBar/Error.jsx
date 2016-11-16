import React from 'react'
import { Message, Icon } from 'semantic-ui-react'

const ErrorMessage = () => (
  <Message size="mini" icon negative>
    <Icon name="minus circle" />
    <Message.Header>Error</Message.Header>
  </Message>
)

export default ErrorMessage
