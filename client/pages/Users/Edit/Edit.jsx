import React from 'react'
import { Button, Form, Loader, Message } from 'semantic-ui-react'

import rqst from 'helpers/request'
import statuses from 'helpers/userStatuses'
import { wrapper } from 'helpers/locale'
import styles from './styles'

class Edit extends React.Component {
  state = {
    rolesList: [],
    standardDataAccess: [],
    fetchingRoles: true,
    fetchingStandardDataAccess: true,
    rolesFailMessage: undefined,
    standardDataAccessMessage: undefined,
  }
  componentDidMount() {
    this.props.fetchUser(this.props.id)
    this.fetchRoles()
    this.fetchStandardDataAccess()
  }
  fetchRoles = () => {
    rqst({
      url: '/api/roles',
      onSuccess: ({ result }) => {
        this.setState(({
          rolesList: result,
          fetchingRoles: false,
        }))
      },
      onFail: () => {
        this.setState(({
          rolesFailMessage: 'failed loading roles',
          fetchingRoles: false,
        }))
      },
      onError: () => {
        this.setState(({
          rolesFailMessage: 'error while fetching roles',
          fetchingRoles: false,
        }))
      },
    })
  }
  fetchStandardDataAccess() {
    rqst({
      url: '/api/accessAttributes/dataAttributes',
      onSuccess: (result) => {
        this.setState(({
          standardDataAccess: result,
          fetchingStandardDataAccess: false,
        }))
      },
      onFail: () => {
        this.setState(({
          standardDataAccessMessage: 'failed loading standard data access',
          fetchingStandardDataAccess: false,
        }))
      },
      onError: () => {
        this.setState(({
          standardDataAccessFailMessage: 'error while fetching standard data access',
          fetchingStandardDataAccess: false,
        }))
      },
    })
  }
  renderForm() {
    const { user, editForm, submitUser, localize } = this.props
    const handleSubmit = (e) => {
      e.preventDefault()
      submitUser(user)
    }
    const handleChange = propName => (e) => { editForm({ propName, value: e.target.value }) }
    const handleSelect = (e, { name, value }) => { editForm({ propName: name, value }) }
    return user !== undefined
      ? (
        <Form className={styles.form} onSubmit={handleSubmit}>
          <h2>{localize('EditUser')}</h2>
          <Form.Input
            value={user.name}
            onChange={handleChange('name')}
            name="name"
            label={localize('UserName')}
            placeholder={localize('RobertDiggs')}
          />
          <Form.Input
            value={user.login}
            onChange={handleChange('login')}
            name="login"
            label={localize('UserLogin')}
            placeholder="e.g. rdiggs"
          />
          <Form.Input
            value={user.newPassword || ''}
            onChange={handleChange('newPassword')}
            name="newPassword"
            type="password"
            label={localize('UsersNewPassword')}
            placeholder={localize('TypeStrongPasswordHere')}
          />
          <Form.Input
            value={user.confirmPassword || ''}
            onChange={handleChange('confirmPassword')}
            name="confirmPassword"
            type="password"
            label={localize('ConfirmPassword')}
            placeholder={localize('TypeNewPasswordAgain')}
            error={user.confirmPassword !== user.newPassword}
          />
          <Form.Input
            value={user.email}
            onChange={handleChange('email')}
            name="email"
            type="email"
            label={localize('UserEmail')}
            placeholder="e.g. robertdiggs@site.domain"
          />
          <Form.Input
            value={user.phone}
            onChange={handleChange('phone')}
            name="phone"
            type="tel"
            label={localize('UserPhone')}
            placeholder="555123456"
          />
          {this.state.fetchingRoles
            ? <Loader content="fetching roles" active />
            : <Form.Select
              value={user.assignedRoles}
              onChange={handleSelect}
              options={this.state.rolesList.map(r => ({ value: r.name, text: r.name }))}
              name="assignedRoles"
              label={localize('AssignedRoles')}
              placeholder={localize('SelectOrSearchRoles')}
              multiple
              search
            />}
          <Form.Select
            value={user.status}
            onChange={handleSelect}
            options={statuses.map(s => ({ value: s.key, text: localize(s.value) }))}
            name="status"
            label={localize('UserStatus')}
          />
          {this.state.fetchingStandardDataAccess
            ? <Loader content={localize('FetchingStandardDataAccess')} />
            : <Form.Select
              value={user.dataAccess}
              onChange={handleSelect}
              options={this.state.standardDataAccess.map(r => ({ value: r, text: localize(r) }))}
              name="dataAccess"
              label={localize('DataAccess')}
              placeholder={localize('SelectOrSearchStandardDataAccess')}
              multiple
              search
            />}
          <Form.Input
            value={user.description}
            onChange={handleChange('description')}
            name="description"
            label={localize('Description')}
            placeholder={localize('NSO_Employee')}
          />
          <Button className={styles.sybbtn} type="submit" primary>{localize('Submit')}</Button>
          {this.state.rolesFailMessage
            && <div>
              <Message content={this.state.rolesFailMessage} negative />
              <Button onClick={() => { this.fetchRoles() }} type="button">
                {localize('TryReloadRoles')}
              </Button>
            </div>}
        </Form>
      ) : <Loader active />
  }
  render() {
    return (
      <div className={styles.userEdit}>
        {this.renderForm()}
      </div>
    )
  }
}

Edit.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(Edit)
