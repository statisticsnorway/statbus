import React from 'react'
import { Link } from 'react-router'
import { Button, Form, Loader, Icon } from 'semantic-ui-react'
import R from 'ramda'

import SchemaForm from 'components/Form'
import { systemFunction as sF } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import accountSchema from './schema'
import styles from './styles'

const { func, shape, string } = React.PropTypes

class EditDetails extends React.Component {

  static propTypes = {
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

  componentDidMount() {
    this.props.fetchAccount()
  }

  shouldComponentUpdate(nextProps, nextState) {
    if (this.props.localize.lang !== nextProps.localize.lang) return true
    return !R.equals(this.props, nextProps) || !R.equals(this.state, nextState)
  }

  handleEdit = (e, { name, value }) => {
    this.props.editForm({ name, value })
  }

  handleSubmit = (e) => {
    e.preventDefault()
    if (sF('AccountEdit')) {
      this.props.submitAccount(this.props.account)
    }
  }

  renderEditForm() {
    const {
      account: { name, currentPassword, newPassword, confirmPassword, phone, email },
      localize,
    } = this.props
    return (
      <div className={styles.accountEdit}>
        <SchemaForm
          data={this.props.account}
          schema={accountSchema}
          onSubmit={this.handleSubmit}
          className={styles.form}
        >
          <Form.Input
            value={name}
            onChange={this.handleEdit}
            name="name"
            label={localize('UserName')}
            placeholder={localize('NameValueRequired')}
            required
          />
          <Form.Input
            value={currentPassword || ''}
            onChange={this.handleEdit}
            name="currentPassword"
            type="password"
            label={localize('CurrentPassword')}
            placeholder={localize('CurrentPassword')}
            required
          />
          <Form.Input
            value={newPassword || ''}
            onChange={this.handleEdit}
            name="newPassword"
            type="password"
            label={localize('NewPassword_LeaveItEmptyIfYouWillNotChangePassword')}
            placeholder={localize('NewPassword')}
          />
          <Form.Input
            value={confirmPassword || ''}
            onChange={this.handleEdit}
            name="confirmPassword"
            type="password"
            label={localize('ConfirmPassword')}
            placeholder={localize('ConfirmPassword')}
            error={newPassword
              && newPassword.length > 0
              && newPassword !== confirmPassword}
          />
          <Form.Input
            value={phone || ''}
            onChange={this.handleEdit}
            name="phone"
            type="tel"
            label={localize('Phone')}
            placeholder={localize('PhoneValueRequired')}
          />
          <Form.Input
            value={email}
            onChange={this.handleEdit}
            name="email"
            type="email"
            label={localize('Email')}
            placeholder={localize('EmailValueRequired')}
            required
          />
          <div>
            <Button
              as={Link} to="/"
              content={localize('Back')}
              icon={<Icon size="large" name="chevron left" />}
              floated="left"
              size="small"
              color="grey"
              type="button"
            />
            <Button
              content={localize('Submit')}
              type="submit"
              floated="right"
              primary
            />
          </div>
        </SchemaForm>
      </div>
    )
  }

  render() {
    return (
      <div>
        <h2>{this.props.localize('EditAccount')}</h2>
        {this.props.account === undefined
          ? <Loader active />
          : this.renderEditForm()}
      </div>
    )
  }
}

export default wrapper(EditDetails)
