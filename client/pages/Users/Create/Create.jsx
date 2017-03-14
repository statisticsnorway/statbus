import React from 'react'
import { Link } from 'react-router'
import { Button, Form, Loader, Message, Icon } from 'semantic-ui-react'

import DataAccess from 'components/DataAccess'
import rqst from 'helpers/request'
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
    regionsList: [],
    rolesList: [],
    fetchingRoles: true,
    fetchingStandardDataAccess: true,
    rolesFailMessage: undefined,
    standardDataAccessMessage: undefined,
    regionsFailMessage: undefined,
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

  fetchStandardDataAccess = () => {
    rqst({
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
      onError: () => {
        this.setState(({
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
        this.setState({
          regionsList: [{ value: '', text: localize('RegionNotSelected') }, ...result.map(v => ({ value: v.id, text: v.name }))],
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
    this.setState(s => ({ data: { ...s.data, [name]: value } }))
  }

  handleDataAccessChange = ({ name, type }) => {
    this.setState((s) => {
      const item = s.data.dataAccess[type].find(x => x.name === name)
      const items = [
        ...s.data.dataAccess[type].filter(x => x.name !== name),
        { ...item, allowed: !item.allowed },
      ]
      return { data: { ...s.data, dataAccess: { ...s.data.dataAccess, [type]: items } } }
    })
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
      fetchingRegions, regionsFailMessage,
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
              dataAccess={data.dataAccess}
              onChange={this.handleDataAccessChange}
              label={localize('DataAccess')}
            />}
          <Form.Select
            name="regionId"
            value={data.regionId || ''}
            onChange={this.handleEdit}
            options={this.state.regionsList}
            label={localize('Region')}
            placeholder={localize('RegionNotSelected')}
            search
            disabled={this.state.fetchingRegions}
          />
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
            || fetchingStandardDataAccess
            || fetchingRegions}
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
          {regionsFailMessage
            && <div>
              <Message content={regionsFailMessage} negative />
              <Button onClick={this.fetchRegions} type="button">
                {localize('TryReloadRegions')}
              </Button>
            </div>}
        </Form>
      </div>
    )
  }
}

export default wrapper(Create)
