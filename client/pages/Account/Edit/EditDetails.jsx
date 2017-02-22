import React from 'react'
import { Button, Form, Loader } from 'semantic-ui-react'

import { systemFunction as sF } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'

class EditDetails extends React.Component {

  componentDidMount() {
    this.props.fetchAccount()
  }

  handleSubmit = (e) => {
    e.preventDefault()
    if (sF('AccountEdit')) {
      const { account, submitAccount } = this.props
      submitAccount(account)
    }
  }

  render() {
    const { account, editForm, localize } = this.props
    const handleEdit = propName => (e) => { editForm({ propName, value: e.target.value }) }
    return (
      <div>
        <h2>{localize('EditAccount')}</h2>
        {account === undefined
          ? <Loader active />
          : <Form onSubmit={this.handleSubmit}>
            <Form.Input
              value={account.name}
              onChange={handleEdit('name')}
              name="name"
              label={localize('Name')}
              placeholder={localize('NameValueRequired')}
              required
            />
            <Form.Input
              value={account.currentPassword || ''}
              onChange={handleEdit('currentPassword')}
              name="currentPassword"
              type="password"
              label={localize('CurrentPassword')}
              placeholder={localize('CurrentPassword')}
              required
            />
            <Form.Input
              value={account.newPassword || ''}
              onChange={handleEdit('newPassword')}
              name="newPassword"
              type="password"
              label={localize('NewPassword_LeaveItEmptyIfYouWillNotChangePassword')}
              placeholder={localize('NewPassword')}
            />
            <Form.Input
              value={account.confirmPassword || ''}
              onChange={handleEdit('confirmPassword')}
              name="confirmPassword"
              type="password"
              label={localize('ConfirmPassword')}
              placeholder={localize('ConfirmPassword')}
              error={account.newPassword
                && account.newPassword.length > 0
                && account.newPassword !== account.confirmPassword}
            />
            <Form.Input
              value={account.phone}
              onChange={handleEdit('phone')}
              name="phone"
              type="tel"
              label={localize('Phone')}
              placeholder={localize('PhoneValueRequired')}
            />
            <Form.Input
              value={account.email}
              onChange={handleEdit('email')}
              name="email"
              type="email"
              label={localize('Email')}
              placeholder={localize('EmailValueRequired')}
              required
            />
            <Button type="submit" primary>{localize('Submit')}</Button>
          </Form>}
      </div>
    )
  }
}

const { func, shape, string } = React.PropTypes

EditDetails.propTypes = {
  account: shape({
    name: string.isRequired,
    currentPassword: string.isRequired,
    newPassword: string,
    confirmPassword: string,
    phone: string,
    email: string.isRequired,
  }).isRequired,
  fetchAccount: func.isRequired,
  editForm: func.isRequired,
  submitAccount: func.isRequired,
  localize: func.isRequired,
}

export default wrapper(EditDetails)
