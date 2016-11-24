import React from 'react'
import { Button, Form, Loader } from 'semantic-ui-react'

export default class EditDetails extends React.Component {
  componentDidMount() {
    this.props.fetchAccount()
  }
  render() {
    const { account, editForm, submitAccount } = this.props
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
              required
            />
            <Form.Input
              value={account.currentPassword || ''}
              onChange={handleEdit('currentPassword')}
              name="currentPassword"
              type="password"
              label="Current password"
              placeholder="current password"
              required
            />
            <Form.Input
              value={account.newPassword || ''}
              onChange={handleEdit('newPassword')}
              name="newPassword"
              type="password"
              label="New password (leave it empty if you won't change password)"
              placeholder="new password"
            />
            <Form.Input
              value={account.confirmPassword || ''}
              onChange={handleEdit('confirmPassword')}
              name="confirmPassword"
              type="password"
              label="Confirm password"
              placeholder="confirm password"
              error={account.newPassword
                && account.newPassword.length > 0
                && account.newPassword !== account.confirmPassword}
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
              required
            />
            <Button type="submit" primary>submit</Button>
          </Form>}
      </div>
    )
  }
}
