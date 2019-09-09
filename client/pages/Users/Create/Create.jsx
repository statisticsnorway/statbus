import React from 'react'
import { func, oneOfType, bool, object } from 'prop-types'
import { Button, Form, Loader, Message, Icon, Popup } from 'semantic-ui-react'
import { equals } from 'ramda'

import ActivityTree from 'components/ActivityTree'
import RegionTree from 'components/RegionTree'
import { internalRequest } from 'helpers/request'
import { userStatuses, roles } from 'helpers/enums'
import { distinctBy } from 'helpers/enumerable'
import { hasValue } from 'helpers/validation'
import styles from './styles.pcss'

class Create extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    submitUser: func.isRequired,
    navigateBack: func.isRequired,
    checkExistLogin: func.isRequired,
    loginError: oneOfType([bool, object]),
    checkExistLoginSuccess: func.isRequired,
  }

  state = {
    data: {
      name: '',
      login: '',
      email: '',
      phone: '',
      password: '',
      confirmPassword: '',
      assignedRole: roles.admin,
      status: 2,
      dataAccess: {
        localUnit: [],
        legalUnit: [],
        enterpriseGroup: [],
        enterpriseUnit: [],
      },
      userRegions: [],
      description: '',
      activiyCategoryIds: [],
    },
    regionTree: undefined,
    rolesList: [],
    fetchingRoles: true,
    fetchingRegions: true,
    fetchingActivities: true,
    rolesFailMessage: undefined,
    activityTree: [],
  }

  componentDidMount() {
    this.props.checkExistLoginSuccess(false)
    this.fetchRegionTree()
    this.fetchRoles()
    this.fetchActivityTree()
  }

  shouldComponentUpdate(nextProps, nextState) {
    return (
      this.props.localize.lang !== nextProps.localize.lang ||
      !equals(this.props, nextProps) ||
      !equals(this.state, nextState)
    )
  }

  setActivities = (activities) => {
    this.setState(s => ({
      data: {
        ...s.data,
        activiyCategoryIds: activities.filter(x => x !== 'all'),
        isAllActivitiesSelected: activities.some(x => x === 'all'),
      },
    }))
  }

  fetchRegionTree = () =>
    internalRequest({
      url: '/api/Regions/GetAllRegionTree',
      method: 'get',
      onSuccess: (result) => {
        this.setState({
          regionTree: result,
          fetchingRegions: false,
        })
      },
      onFail: () => {
        this.setState({
          rolesFailMessage: 'failed loading regions',
          fetchingRegions: false,
        })
      },
    })

  fetchRoles = () => {
    internalRequest({
      url: '/api/roles',
      onSuccess: ({ result }) => {
        this.setState({
          rolesList: result,
          fetchingRoles: false,
        })
      },
      onFail: () => {
        this.setState({
          rolesFailMessage: 'failed loading roles',
          fetchingRoles: false,
        })
      },
    })
  }

  fetchActivityTree = (parentId = 0) => {
    internalRequest({
      url: `/api/roles/fetchActivityTree?parentId=${parentId}`,
      onSuccess: (result) => {
        this.setState({
          activityTree: distinctBy([...this.state.activityTree, ...result], x => x.id),
          fetchingActivities: false,
        })
      },
      onFail: () => {
        this.setState({
          rolesFailMessage: 'failed loading activities',
          fetchingActivities: false,
        })
      },
    })
  }

  handleEdit = (e, { name, value }) => {
    this.setState(s => ({ data: { ...s.data, [name]: value } }))
  }

  checkExistLogin = (e) => {
    const loginName = e.target.value
    if (loginName.length > 0) this.props.checkExistLogin(loginName)
  }

  handleSubmit = (e) => {
    e.preventDefault()
    this.props.submitUser(this.state.data)
  }

  handleCheck = value => this.handleEdit(null, { name: 'userRegions', value })

  render() {
    const { localize, navigateBack, loginError } = this.props
    const {
      data,
      fetchingRoles,
      fetchingRegions,
      fetchingActivities,
      rolesList,
      rolesFailMessage,
      regionTree,
      activityTree,
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
            maxLength={64}
            placeholder="e.g. Robert Diggs"
            autoComplete="off"
            required
          />
          <Form.Input
            name="login"
            value={data.login}
            onChange={this.handleEdit}
            onBlur={this.checkExistLogin}
            label={localize('UserLogin')}
            placeholder="e.g. rdiggs"
            autoComplete="off"
            required
          />
          {loginError && (
            <Message size="small" visible error>
              {localize('LoginError')}
            </Message>
          )}
          <Form.Input
            name="email"
            value={data.email}
            onChange={this.handleEdit}
            type="email"
            label={localize('UserEmail')}
            placeholder="e.g. robertdiggs@site.domain"
            autoComplete="off"
            required
          />
          <Popup
            trigger={
              <Form.Input
                name="password"
                value={data.password}
                onChange={this.handleEdit}
                type="password"
                label={localize('UserPassword')}
                placeholder={localize('TypeStrongPasswordHere')}
                autoComplete="off"
                required
              />
            }
            content={localize('PasswordLengthRestriction')}
            open={hasValue(data.password) && data.password.length < 6}
          />
          <Popup
            trigger={
              <Form.Input
                name="confirmPassword"
                value={data.confirmPassword}
                onChange={this.handleEdit}
                type="password"
                label={localize('ConfirmPassword')}
                placeholder={localize('TypePasswordAgain')}
                error={data.confirmPassword !== data.password}
                autoComplete="off"
                required
              />
            }
            content={localize('PasswordLengthRestriction')}
            open={hasValue(data.confirmPassword) && data.confirmPassword.length < 6}
          />
          <Form.Input
            name="phone"
            value={data.phone}
            onChange={this.handleEdit}
            type="number"
            label={localize('UserPhone')}
            placeholder="555123456"
            autoComplete="off"
          />
          {fetchingRoles ? (
            <Loader content="fetching roles" active />
          ) : (
            <Form.Select
              name="assignedRole"
              value={data.assignedRole}
              onChange={this.handleEdit}
              options={rolesList.map(r => ({ value: r.name, text: localize(r.name) }))}
              label={localize('AssignedRoles')}
              placeholder={localize('SelectOrSearchRoles')}
              autoComplete="off"
              search
            />
          )}
          <Form.Select
            name="status"
            value={data.status}
            onChange={this.handleEdit}
            options={[...userStatuses].map(([k, v]) => ({ value: k, text: localize(v) }))}
            autoComplete="off"
            label={localize('UserStatus')}
          />
          {!fetchingRoles && data.assignedRole !== roles.admin && (
            <ActivityTree
              name="activiyCategoryIds"
              label="ActivityCategoryLookup"
              dataTree={activityTree}
              loaded={!fetchingActivities}
              checked={data.activiyCategoryIds}
              callBack={this.setActivities}
              localize={localize}
              loadNode={this.fetchActivityTree}
            />
          )}
          {!fetchingRoles && data.assignedRole !== roles.admin && (
            <RegionTree
              name="RegionTree"
              label="Regions"
              loaded={!fetchingRegions}
              dataTree={regionTree}
              checked={data.userRegions}
              callBack={this.handleCheck}
              localize={localize}
            />
          )}
          <Form.Input
            name="description"
            value={data.description}
            onChange={this.handleEdit}
            label={localize('Description')}
            placeholder={localize('NSO_Employee')}
            autoComplete="off"
            maxLength={64}
          />
          <Button
            content={localize('Back')}
            onClick={navigateBack}
            icon={<Icon size="large" name="chevron left" />}
            size="small"
            color="grey"
            type="button"
          />
          <Button
            content={localize('Submit')}
            type="submit"
            disabled={fetchingRoles || fetchingActivities || fetchingRegions || loginError}
            floated="right"
            primary
          />
          {rolesFailMessage && (
            <div>
              <Message content={rolesFailMessage} negative />
              <Button onClick={this.fetchRoles} type="button">
                {localize('TryReloadRoles')}
              </Button>
            </div>
          )}
        </Form>
      </div>
    )
  }
}

export default Create
