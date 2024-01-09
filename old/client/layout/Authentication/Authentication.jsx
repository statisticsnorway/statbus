import React, { useState } from 'react'
import { Button, Modal, Form } from 'semantic-ui-react'

const Authentication = ({ open, localize, sendAuthenticationRequest, hideAuthentication }) => {
  const [credentials, setCredentials] = useState({ login: '', password: '', rememberMe: true })

  const handleChange = (e, { name, value }) => {
    setCredentials({ ...credentials, [name]: value })
  }

  const sendRequest = () => {
    sendAuthenticationRequest(credentials)
  }

  return (
    <Modal open={open} size="mini">
      <Modal.Header content={localize('NSCRegistry')} />
      <Modal.Content>
        <Form>
          <Form.Input
            label={localize('Login')}
            name="login"
            value={credentials.login}
            onChange={handleChange}
          />

          <Form.Input
            label={localize('Password')}
            name="password"
            type="password"
            value={credentials.password}
            onChange={handleChange}
          />
        </Form>
      </Modal.Content>
      <Modal.Actions>
        <Button.Group>
          <Button onClick={hideAuthentication} content={localize('ButtonCancel')} negative />
          <Button content={localize('Submit')} onClick={sendRequest} positive />
        </Button.Group>
      </Modal.Actions>
    </Modal>
  )
}

export default Authentication
