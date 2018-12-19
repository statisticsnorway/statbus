import React, { Component } from 'react'
import { Button, Modal, Form } from 'semantic-ui-react'

export default class Authentication extends Component {
  state = { login: '', password: '', rememberMe: true }

  handleChange = (e, { name, value }) => {
    this.setState(state => ({ ...state, [name]: value }))
  }

  sendRequest = () => {
    this.props.sendAuthenticationRequest(this.state)
  }

  render() {
    const { open, localize } = this.props

    return (
      <Modal open={open} size="mini">
        <Modal.Header content={localize('NSCRegistry')} />
        <Modal.Content>
          <Form>
            <Form.Input
              label={localize('Login')}
              name="login"
              value={this.state.login}
              onChange={this.handleChange}
            />

            <Form.Input
              label={localize('Password')}
              name="password"
              type="password"
              value={this.state.password}
              onChange={this.handleChange}
            />
          </Form>
        </Modal.Content>
        <Modal.Actions>
          <Button.Group>
            <Button
              onClick={this.props.hideAuthentication}
              content={localize('ButtonCancel')}
              negative
            />
            <Button content={localize('Submit')} onClick={this.sendRequest} positive />
          </Button.Group>
        </Modal.Actions>
      </Modal>
    )
  }
}
