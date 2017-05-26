import React from 'react'
import { Link } from 'react-router'
import { Button, Form, Loader, Message, Icon } from 'semantic-ui-react'
import R from 'ramda'

import DataAccess from 'components/DataAccess'
import { internalRequest } from 'helpers/request'
import statuses from 'helpers/userStatuses'
import { wrapper } from 'helpers/locale'
import styles from './styles'

const { func } = React.PropTypes

class Create extends React.Component {

  static propTypes = {
    localize: func.isRequired,
    submitUser: func.isRequired,
  }

  state = {
    data: {
      name: '',
      login: '',
      email: '',
      phone: '',
      password: '',
      confirmPassword: '',
      assignedRoles: [],
      status: 1,
      dataAccess: {
        localUnit: [],
        legalUnit: [],
        enterpriseGroup: [],
        enterpriseUnit: [],
      },
      description: '',
    },
    rolesList: [],
    fetchingRoles: true,
    fetchingStandardDataAccess: true,
    rolesFailMessage: undefined,
    standardDataAccessMessage: undefined,
  }

  componentDidMount() {
    this.fetchRoles()
    this.fetchStandardDataAccess()
  }

  shouldComponentUpdate(nextProps, nextState) {
    return this.props.localize.lang !== nextProps.localize.lang
      || !R.equals(this.props, nextProps)
      || !R.equals(this.state, nextState)
  }

  fetchRoles = () => {
    internalRequest({
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
    })
  }

  fetchStandardDataAccess = () => {
    internalRequest({
      url: '/api/accessAttributes/dataAttributes',
      onSuccess: (result) => {
        this.setState(s => ({
          data: {
            ...s.data,
            dataAccess: result,
          },
          fetchingStandardDataAccess: false,
        }))
      },
      onFail: () => {
        this.setState(({
          standardDataAccessMessage: 'failed loading standard data access',
          fetchingStandardDataAccess: false,
        }))
      },
    })
  }

  handleEdit = (e, { name, value }) => {
    this.setState(s => ({ data: { ...s.data, [name]: value } }))
  }

  handleSubmit = (e) => {
    e.preventDefault()
    this.props.submitUser(this.state.data)
  }

  render() {
    const { localize } = this.props
    const {
      data,
      fetchingRoles, rolesList, rolesFailMessage,
      fetchingStandardDataAccess,
    } = this.state
    return (
      <div className={styles.root}>
        <Form onSubmit={this.handleSubmit}>
          <h2>{localize('CreateNewUser')}</h2>
          <Form.Input
            name="name"
            value={data.name}
            onChange={this.handleEdit}
            label={localize('UserName')}
            placeholder="e.g. Robert Diggs"
            required
          />
          <Form.Input
            name="login"
            value={data.login}
            onChange={this.handleEdit}
            label={localize('UserLogin')}
            placeholder="e.g. rdiggs"
            required
          />
          <Form.Input
            name="password"
            value={data.password}
            onChange={this.handleEdit}
            type="password"
            label={localize('UserPassword')}
            placeholder={localize('TypeStrongPasswordHere')}
            required
          />
          <Form.Input
            name="confirmPassword"
            value={data.confirmPassword}
            onChange={this.handleEdit}
            type="password"
            label={localize('ConfirmPassword')}
            placeholder={localize('TypePasswordAgain')}
            error={data.confirmPassword !== data.password}
            required
          />
          <Form.Input
            name="email"
            value={data.email}
            onChange={this.handleEdit}
            type="email"
            label={localize('UserEmail')}
            placeholder="e.g. robertdiggs@site.domain"
            required
          />
          <Form.Input
            name="phone"
            value={data.phone}
            onChange={this.handleEdit}
            type="tel"
            label={localize('UserPhone')}
            placeholder="555123456"
          />
          {fetchingRoles
            ? <Loader content="fetching roles" active />
            : <Form.Select
              name="assignedRoles"
              value={data.assignedRoles}
              onChange={this.handleEdit}
              options={rolesList.map(r => ({ value: r.name, text: r.name }))}
              label={localize('AssignedRoles')}
              placeholder={localize('SelectOrSearchRoles')}
              multiple
              search
            />}
          <Form.Select
            name="status"
            value={data.status}
            onChange={this.handleEdit}
            options={statuses.map(s => ({ value: s.key, text: localize(s.value) }))}
            label={localize('UserStatus')}
          />
          {fetchingStandardDataAccess
            ? <Loader content="fetching standard data access" />
            : <DataAccess
              name="dataAccess"
              value={data.dataAccess}
              onChange={this.handleEdit}
              label={localize('DataAccess')}
            />}
          <Form.Input
            name="description"
            value={data.description}
            onChange={this.handleEdit}
            label={localize('Description')}
            placeholder={localize('NSO_Employee')}
          />
          <Button
            as={Link} to="/users"
            content={localize('Back')}
            icon={<Icon size="large" name="chevron left" />}
            size="small"
            color="grey"
            type="button"
          />
          <Button
            content={localize('Submit')}
            type="submit"
            disabled={fetchingRoles
            || fetchingStandardDataAccess}
            floated="right"
            primary
          />
          {rolesFailMessage
            && <div>
              <Message content={rolesFailMessage} negative />
              <Button onClick={this.fetchRoles} type="button">
                {localize('TryReloadRoles')}
              </Button>
            </div>}
        </Form>
      </div>
    )
  }
}

export default wrapper(Create)
