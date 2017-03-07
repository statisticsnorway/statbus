import React from 'react'
import { Button, Form, Loader, Message, Icon } from 'semantic-ui-react'
import { Link } from 'react-router'

import rqst from 'helpers/request'
import statuses from 'helpers/userStatuses'
import { wrapper } from 'helpers/locale'
import styles from './styles'

class Create extends React.Component {
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
    password: '',
    confirmPassword: '',
  }
  componentDidMount() {
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
    const { submitUser, localize } = this.props
    const handleSubmit = (e, { formData }) => {
      e.preventDefault()
      submitUser(formData)
    }
    const handleChange = propName => (e) => {
      e.persist()
      this.setState(s => ({ ...s, [propName]: e.target.value }))
    }
    return (
      <Form className={styles.form} onSubmit={handleSubmit}>
        <h2>{localize('CreateNewUser')}</h2>
        <Form.Input
          name="name"
          label={localize('UserName')}
          required
          placeholder="e.g. Robert Diggs"
        />
        <Form.Input
          name="login"
          label={localize('UserLogin')}
          required
          placeholder="e.g. rdiggs"
        />
        <Form.Input
          value={this.state.password}
          onChange={handleChange('password')}
          name="password"
          type="password"
          required
          label={localize('UserPassword')}
          placeholder={localize('TypeStrongPasswordHere')}
        />
        <Form.Input
          value={this.state.confirmPassword}
          onChange={handleChange('confirmPassword')}
          name="confirmPassword"
          type="password"
          required
          label={localize('ConfirmPassword')}
          placeholder={localize('TypePasswordAgain')}
          error={this.state.confirmPassword !== this.state.password}
        />
        <Form.Input
          name="email"
          type="email"
          required
          label={localize('UserEmail')}
          placeholder="e.g. robertdiggs@site.domain"
        />
        <Form.Input
          name="phone"
          type="tel"
          label={localize('UserPhone')}
          placeholder="555123456"
        />
        <Form.Select
          options={this.state.rolesList.map(r => ({ value: r.name, text: r.name }))}
          name="assignedRoles"
          label={localize('AssignedRoles')}
          placeholder={localize('SelectOrSearchRoles')}
          multiple
          search
          disabled={this.state.fetchingRoles}
        />
        <Form.Select
          options={statuses.map(s => ({ value: s.key, text: localize(s.value) }))}
          name="status"
          defaultValue={1}
          label={localize('UserStatus')}
        />
        <Form.Select
          options={this.state.standardDataAccess.map(r => ({ value: r, text: localize(r) }))}
          name="dataAccess"
          label={localize('DataAccess')}
          placeholder={localize('SelectOrSearchStandardDataAccess')}
          multiple
          search
          disabled={this.state.fetchingStandardDataAccess}
        />
        <Form.Select
          options={this.state.regionsList}
          name="regionId"
          label={localize('Region')}
          placeholder={localize('RegionNotSelected')}
          search
          disabled={this.state.fetchingRegions}
        />
        <Form.Input
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

    )
  }
  render() {
    return (
      <div className={styles.userCreate} >
        {this.renderForm()}
      </div>
    )
  }
}

Create.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(Create)
