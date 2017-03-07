import React from 'react'
import { Link } from 'react-router'
import { Button, Form, Loader, Message, Icon } from 'semantic-ui-react'

import rqst from 'helpers/request'
import statuses from 'helpers/userStatuses'
import { wrapper } from 'helpers/locale'
import styles from './styles'

class Edit extends React.Component {
  state = {
    rolesList: [],
    standardDataAccess: [],
    regionsList: [],
    fetchingRoles: true,
    fetchingStandardDataAccess: true,
    fetchingRegions: true,
    rolesFailMessage: undefined,
    standardDataAccessMessage: undefined,
    regionsFailMessage: undefined,
  }
  componentDidMount() {
    this.props.fetchUser(this.props.id)
    this.fetchRoles()
    this.fetchStandardDataAccess()
    this.fetchRegions()
  }
  fetchRoles = () => {
    rqst({
      url: '/api/roles',
      onSuccess: ({ result }) => {
        this.setState(s => ({
          ...s,
          rolesList: result,
          fetchingRoles: false,
        }))
      },
      onFail: () => {
        this.setState(s => ({
          ...s,
          rolesFailMessage: 'failed loading roles',
          fetchingRoles: false,
        }))
      },
      onError: () => {
        this.setState(s => ({
          ...s,
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
        this.setState(s => ({
          ...s,
          standardDataAccess: result,
          fetchingStandardDataAccess: false,
        }))
      },
      onFail: () => {
        this.setState(s => ({
          ...s,
          standardDataAccessMessage: 'failed loading standard data access',
          fetchingStandardDataAccess: false,
        }))
      },
      onError: () => {
        this.setState(s => ({
          ...s,
          standardDataAccessFailMessage: 'error while fetching standard data access',
          fetchingStandardDataAccess: false,
        }))
      },
    })
  }
  fetchRegions = () => {
    const { localize } = this.props
    rqst({
      url: '/api/regions',
      onSuccess: (result) => {
        this.setState(s => ({
          ...s,
          regionsList: [{ value: '', text: localize('RegionNotSelected') }, ...result.map(v => ({ value: v.id, text: v.name }))],
          fetchingRegions: false,
        }))
      },
      onFail: () => {
        this.setState(s => ({
          ...s,
          rolesFailMessage: 'failed loading regions',
          fetchingRegions: false,
        }))
      },
      onError: () => {
        this.setState(s => ({
          ...s,
          rolesFailMessage: 'error while fetching regions',
          fetchingRegions: false,
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
          <Form.Select
            value={user.assignedRoles}
            onChange={handleSelect}
            options={this.state.rolesList.map(r => ({ value: r.name, text: r.name }))}
            name="assignedRoles"
            label={localize('AssignedRoles')}
            placeholder={localize('SelectOrSearchRoles')}
            multiple
            search
            disabled={this.state.fetchingRoles}
          />
          <Form.Select
            value={user.status}
            onChange={handleSelect}
            options={statuses.map(s => ({ value: s.key, text: localize(s.value) }))}
            name="status"
            label={localize('UserStatus')}
          />
          <Form.Select
            value={user.dataAccess}
            onChange={handleSelect}
            options={this.state.standardDataAccess.map(r => ({ value: r, text: localize(r) }))}
            name="dataAccess"
            label={localize('DataAccess')}
            placeholder={localize('SelectOrSearchStandardDataAccess')}
            multiple
            search
            disabled={this.state.fetchingStandardDataAccess}
          />
          <Form.Select
            value={user.regionId || ''}
            onChange={handleSelect}
            options={this.state.regionsList}
            name="regionId"
            label={localize('Region')}
            placeholder={localize('RegionNotSelected')}
            search
            disabled={this.state.fetchingRegions}
          />
          <Form.Input
            value={user.description}
            onChange={handleChange('description')}
            name="description"
            label={localize('Description')}
            placeholder={localize('NSO_Employee')}
          />
          <Button
            as={Link} to="/users"
            content={localize('Back')}
            icon={<Icon size="large" name="chevron left" />}
            size="small"
            color="gray"
            type="button"
          />
          <Button
            className={styles.sybbtn}
            type="submit"
            disabled={this.state.fetchingRoles ||
            this.state.fetchingStandardDataAccess ||
            this.state.fetchingRegions}
            primary
          >
            {localize('Submit')}
          </Button>
          {this.state.rolesFailMessage
            && <div>
              <Message content={this.state.rolesFailMessage} negative />
              <Button onClick={() => { this.fetchRoles() }} type="button">
                {localize('TryReloadRoles')}
              </Button>
            </div>}
          {this.state.regionsFailMessage
            && <div>
              <Message content={this.state.regionsFailMessage} negative />
              <Button onClick={() => { this.fetchRegions() }} type="button">
                {localize('TryReloadRegions')}
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
