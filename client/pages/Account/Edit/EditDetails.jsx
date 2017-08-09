import React from 'react'
import { Loader, Icon } from 'semantic-ui-react'
import { func } from 'prop-types'

import Form from 'components/SchemaForm'
import { systemFunction as sF } from 'helpers/checkPermissions'
import schema from './schema'
import styles from './styles.pcss'

class EditDetails extends React.Component {

  static propTypes = {
    fetchAccount: func.isRequired,
    submitAccount: func.isRequired,
    localize: func.isRequired,
    navigateBack: func.isRequired,
  }

  state = {
    formData: undefined,
  }

  componentDidMount() {
    this.props.fetchAccount((data) => {
      this.setState({ formData: schema.cast(data) })
    })
  }

  handleFormEdit = (formData) => {
    this.setState({ formData })
  }

  handleSubmit = () => {
    if (sF('AccountEdit')) {
      this.props.submitAccount(this.state.formData)
    }
  }

  renderForm() {
    const { localize, navigateBack } = this.props
    const { formData } = this.state
    return (
      <div className={styles.accountEdit}>
        <Form
          schema={schema}
          value={formData}
          onChange={this.handleFormEdit}
          onSubmit={this.handleSubmit}
          className={styles.form}
        >
          <Form.Text
            name="name"
            label={localize('UserName')}
            placeholder={localize('NameValueRequired')}
            required
          />
          <Form.Text
            name="currentPassword"
            type="password"
            label={localize('CurrentPassword')}
            placeholder={localize('CurrentPassword')}
            required
          />
          <Form.Text
            name="newPassword"
            type="password"
            label={localize('NewPassword_LeaveItEmptyIfYouWillNotChangePassword')}
            placeholder={localize('NewPassword')}
          />
          <Form.Text
            name="confirmPassword"
            type="password"
            label={localize('ConfirmPassword')}
            placeholder={localize('ConfirmPassword')}
          />
          <Form.Text
            name="phone"
            type="tel"
            label={localize('Phone')}
            placeholder={localize('PhoneValueRequired')}
          />
          <Form.Text
            name="email"
            type="email"
            label={localize('Email')}
            placeholder={localize('EmailValueRequired')}
            required
          />
          <Form.Errors />
          <Form.Button
            content={localize('Back')}
            onClick={navigateBack}
            icon={<Icon size="large" name="chevron left" />}
            size="small"
            color="grey"
            type="button"
          />
          <Form.Button
            content={localize('Submit')}
            type="submit"
            floated="right"
            primary
          />
        </Form>
      </div>
    )
  }

  render() {
    return (
      <div>
        <h2>{this.props.localize('EditAccount')}</h2>
        {this.state.formData === undefined
          ? <Loader active />
          : this.renderForm()}
      </div>
    )
  }
}

export default EditDetails
