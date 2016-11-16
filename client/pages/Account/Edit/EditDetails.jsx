import React from 'react'
import { Button, Form, Loader, Message } from 'semantic-ui-react'

import getStatusProps from '../../../helpers/getSemanticStatusProps.js'

export default class EditDetails extends React.Component {
  componentDidMount() {
    this.props.fetchAccount()
  }
  render() {
    const { account, editForm, submitAccount, message, status } = this.props
    const handleSubmit = (e) => {
      e.preventDefault()
      submitAccount(account)
    }
    const handleEdit = propName => (e) => { editForm({ propName, value: e.target.value }) }
    return (
      <div>
        <h2>Edit account</h2>
        {account === undefined
          ? <Loader active />
          : <Form onSubmit={handleSubmit}>
            <Form.Input
              value={account.name}
              onChange={handleEdit('name')}
              name="name"
              label="Name"
              placeholder="name value required"
            />
            <Form.Input
              value={account.currentPassword || ''}
              onChange={handleEdit('currentPassword')}
              name="currentPassword"
              type="password"
              label="Current password"
              placeholder="current password"
            />
            <Form.Input
              value={account.newPassword || ''}
              onChange={handleEdit('newPassword')}
              name="newPassword"
              type="password"
              label="New password (leave empty in case you won't change current one)"
              placeholder="new password"
            />
            <Form.Input
              value={account.confirmPassword || ''}
              onChange={handleEdit('confirmPassword')}
              name="confirmPassword"
              type="password"
              label="Confirm password"
              placeholder="confirm password"
              error={account.newPassword !== account.confirmPassword}
            />
            <Form.Input
              value={account.phone}
              onChange={handleEdit('phone')}
              name="phone"
              type="tel"
              label="Phone"
              placeholder="phone value required"
            />
            <Form.Input
              value={account.email}
              onChange={handleEdit('email')}
              name="email"
              type="email"
              label="Email"
              placeholder="email value required"
            />
            <Button type="submit" primary>submit</Button>
            {message
              && <Message content={message} {...getStatusProps(status)} />}
          </Form>}
      </div>
    )
  }
}
