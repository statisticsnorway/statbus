import React from 'react'
import { Link } from 'react-router'
import { Button, Form, Loader, Message, Icon } from 'semantic-ui-react'

import DataAccess from 'components/DataAccess'
import rqst from 'helpers/request'
import statuses from 'helpers/userStatuses'
import { wrapper } from 'helpers/locale'
import styles from './styles'

const { func } = React.PropTypes

class Edit extends React.Component {

  static propTypes = {
    fetchUser: func.isRequired,
    editForm: func.isRequired,
    submitUser: func.isRequired,
    localize: func.isRequired,
  }

  state = {
    regionsList: [],
    rolesList: [],
    fetchingRoles: true,
    fetchingStandardDataAccess: true,
    rolesFailMessage: undefined,
    standardDataAccessMessage: undefined,
  }

  componentDidMount() {
    this.props.fetchUser(this.props.id)
    this.fetchRoles()
    this.fetchStandardDataAccess(this.props.id)
    this.fetchRegions()
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

  fetchStandardDataAccess(userId) {
    rqst({
      url: `/api/accessAttributes/dataAttributesByUser/${userId}`,
      onSuccess: (result) => {
        this.props.editForm({ name: 'dataAccess', value: result })
        this.state({
          fetchStandardDataAccess: false,
        })
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

  fetchRegions = () => {
    rqst({
      url: '/api/regions',
      onSuccess: (result) => {
        this.setState({
          regionsList: [
            { value: '', text: this.props.localize('RegionNotSelected') },
            ...result.map(v => ({ value: v.id, text: v.name })),
          ],
          fetchingRegions: false,
        })
      },
      onFail: () => {
        this.setState({
          rolesFailMessage: 'failed loading regions',
          fetchingRegions: false,
        })
      },
      onError: () => {
        this.setState({
          rolesFailMessage: 'error while fetching regions',
          fetchingRegions: false,
        })
      },
    })
  }

  handleEdit = (e, { name, value }) => {
    this.props.editForm({ name, value })
  }

  handleSubmit = (e) => {
    e.preventDefault()
    this.props.submitUser(this.props.user)
  }

  handleDataAccessChange = ({ name, type }) => {
    const { user } = this.props
    const item = user.dataAccess[type].find(x => x.name === name)
    const items = [
      ...user.dataAccess[type].filter(x => x.name !== name),
      { ...item, allowed: !item.allowed },
    ]
    this.props.editForm({ name: 'dataAccess', value: { ...user.dataAccess, [type]: items } })
  }

  renderForm() {
    const { user, localize } = this.props
    return (
      <Form className={styles.form} onSubmit={this.handleSubmit}>
        <h2>{localize('EditUser')}</h2>
        <Form.Input
          value={user.name}
          onChange={this.handleEdit}
          name="name"
          label={localize('UserName')}
          placeholder={localize('RobertDiggs')}
        />
        <Form.Input
          value={user.login}
          onChange={this.handleEdit}
          name="login"
          label={localize('UserLogin')}
          placeholder={localize('LoginPlaceholder')}
        />
        <Form.Input
          value={user.newPassword || ''}
          onChange={this.handleEdit}
          name="newPassword"
          type="password"
          label={localize('UsersNewPassword')}
          placeholder={localize('TypeStrongPasswordHere')}
        />
        <Form.Input
          value={user.confirmPassword || ''}
          onChange={this.handleEdit}
          name="confirmPassword"
          type="password"
          label={localize('ConfirmPassword')}
          placeholder={localize('TypeNewPasswordAgain')}
          error={user.confirmPassword !== user.newPassword}
        />
        <Form.Input
          value={user.email}
          onChange={this.handleEdit}
          name="email"
          type="email"
          label={localize('UserEmail')}
          placeholder={localize('EmailPlaceholder')}
        />
        <Form.Input
          value={user.phone}
          onChange={this.handleEdit}
          name="phone"
          type="tel"
          label={localize('UserPhone')}
          placeholder="555123456"
        />
        {this.state.fetchingRoles
          ? <Loader content={localize('fetching roles')} active />
          : <Form.Select
            value={user.assignedRoles}
            onChange={this.handleEdit}
            options={this.state.rolesList.map(r => ({ value: r.name, text: r.name }))}
            name="assignedRoles"
            label={localize('AssignedRoles')}
            placeholder={localize('SelectOrSearchRoles')}
            multiple
            search
          />}
        <Form.Select
          value={user.status}
          onChange={this.handleEdit}
          options={statuses.map(s => ({ value: s.key, text: localize(s.value) }))}
          name="status"
          label={localize('UserStatus')}
        />
        {this.state.fetchingStandardDataAccess && user.dataAccess
          ? <Loader content="fetching standard data access" />
          : <DataAccess
            dataAccess={user.dataAccess}
            onChange={this.handleDataAccessChange}
            label={localize('DataAccess')}
          />}
        <Form.Select
          value={user.regionId || ''}
          onChange={this.handleEdit}
          options={this.state.regionsList}
          name="regionId"
          label={localize('Region')}
          placeholder={localize('RegionNotSelected')}
          search
          disabled={this.state.fetchingRegions}
        />
        <Form.Input
          value={user.description}
          onChange={this.handleEdit}
          name="description"
          label={localize('Description')}
          placeholder={localize('NSO_Employee')}
        />
        <Button
          as={Link} to="/users"
          content={localize('Back')}
          icon={<Icon size="large" name="chevron left" />}
          floated="left"
          size="small"
          color="grey"
          type="button"
        />
        <Button
          content={localize('Submit')}
          floated="right"
          type="submit"
          primary
        />
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
      <div className={styles.userEdit}>
        {this.props.user !== undefined
          ? this.renderForm()
          : <Loader active />}
      </div>
    )
  }
}

export default wrapper(Edit)
