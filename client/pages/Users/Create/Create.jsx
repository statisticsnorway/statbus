import React from 'react'
import { func } from 'prop-types'
import { Button, Form, Loader, Message, Icon } from 'semantic-ui-react'
import { equals } from 'ramda'

import ActivityTree from 'components/ActivityTree'
import RegionTree from 'components/RegionTree'
import { internalRequest } from 'helpers/request'
import { userStatuses, roles } from 'helpers/enums'
import styles from './styles.pcss'

class Create extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    submitUser: func.isRequired,
    navigateBack: func.isRequired,
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
      status: 1,
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
    rolesFailMessage: undefined,
    activityTree: [],
  }

  componentDidMount() {
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
    this.setState(s => ({ data: { ...s.data, activiyCategoryIds: activities.filter(x => x !== 'all'),isAllActivitiesSelected: activities.some(x => x === 'all') } }))
  }

  fetchRegionTree = () =>
    internalRequest({
      url: '/api/Regions/GetRegionTree',
      method: 'get',
      onSuccess: (result) => {
        this.setState({ regionTree: result })
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

  handleEdit = (e, { name, value }) => {
    this.setState(s => ({ data: { ...s.data, [name]: value } }))
  }

  fetchActivityTree = (parentId = 0) => {
    internalRequest({
      url: `/api/roles/fetchActivityTree?parentId=${parentId}`,
      onSuccess: (result) => {
        this.setState({
          activityTree: [...this.state.activityTree, ...result],
        })
      },
    })
  }

  handleSubmit = (e) => {
    e.preventDefault()
    this.props.submitUser(this.state.data)
  }

  handleCheck = value => this.handleEdit(null, { name: 'userRegions', value })

  render() {
    const { localize, navigateBack } = this.props
    const {
      data,
      fetchingRoles, rolesList, rolesFailMessage,
      regionTree, activityTree,
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
            name="email"
            value={data.email}
            onChange={this.handleEdit}
            type="email"
            label={localize('UserEmail')}
            placeholder="e.g. robertdiggs@site.domain"
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
            name="phone"
            value={data.phone}
            onChange={this.handleEdit}
            type="number"
            label={localize('UserPhone')}
            placeholder="555123456"
          />
          {fetchingRoles ? (
            <Loader content="fetching roles" active />
          ) : (
            <Form.Select
              name="assignedRole"
              value={data.assignedRole}
              onChange={this.handleEdit}
              options={rolesList.map(r => ({ value: r.name, text: r.name }))}
              label={localize('AssignedRoles')}
              placeholder={localize('SelectOrSearchRoles')}
              search
            />
          )}
          <Form.Select
            name="status"
            value={data.status}
            onChange={this.handleEdit}
            options={[...userStatuses].map(([k, v]) => ({ value: k, text: localize(v) }))}
            label={localize('UserStatus')}
          />
          {activityTree && data.assignedRole !== roles.admin &&
            <ActivityTree
              name="activiyCategoryIds"
              label="ActivityCategoryLookup"
              dataTree={activityTree}
              checked={data.activiyCategoryIds}
              callBack={this.setActivities}
              localize={localize}
              loadNode={this.fetchActivityTree}
            /> }
          {regionTree && data.assignedRole !== roles.admin &&
          <RegionTree
            name="RegionTree"
            label="Regions"
            dataTree={regionTree}
            checked={data.userRegions}
            callBack={this.handleCheck}
            localize={localize}
          />}
          <Form.Input
            name="description"
            value={data.description}
            onChange={this.handleEdit}
            label={localize('Description')}
            placeholder={localize('NSO_Employee')}
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
            disabled={fetchingRoles}
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
