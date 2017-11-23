import React from 'react'
import { func, shape, oneOfType, number, string, arrayOf } from 'prop-types'
import { Button, Form, Loader, Message, Icon } from 'semantic-ui-react'
import { equals } from 'ramda'

import ActivityTree from 'components/ActivityTree'
import DataAccess from 'components/DataAccess'
import RegionTree from 'components/RegionTree'
import { internalRequest } from 'helpers/request'
import styles from './styles.pcss'
import { roles } from 'helpers/enums'

class Edit extends React.Component {
  static propTypes = {
    id: oneOfType([number, string]).isRequired,
    user: shape({}).isRequired,
    fetchUser: func.isRequired,
    fetchRegionTree: func.isRequired,
    editForm: func.isRequired,
    submitUser: func.isRequired,
    localize: func.isRequired,
    navigateBack: func.isRequired,
    regionTree: shape({}),
    activityTree: arrayOf(shape({})).isRequired,
    fetchActivityTree: func.isRequired,
  }
  static defaultProps = {
    regionTree: undefined,
  }

  state = {
    rolesList: [],
    fetchingRoles: true,
    fetchingStandardDataAccess: true,
    rolesFailMessage: undefined,
  }

  componentDidMount() {
    this.props.fetchRegionTree()
    this.props.fetchUser(this.props.id)
    this.fetchRoles()
    this.props.fetchActivityTree()
  }

  shouldComponentUpdate(nextProps, nextState) {
    return (
      this.props.localize.lang !== nextProps.localize.lang ||
      !equals(this.props, nextProps) ||
      !equals(this.state, nextState)
    )
  }

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
    this.props.editForm({ name, value })
  }

  handleSubmit = (e) => {
    e.preventDefault()
    this.props.submitUser(this.props.user)
  }

  setActivities = (activities) => {
    this.props.editForm({ name: 'activiyCategoryIds', value: activities.filter(x => x !== 'all') })
    this.props.editForm({ name: 'isAllActivitiesSelected', value: activities.some(x => x === 'all') })
  }

  handleCheck = value => this.props.editForm({ name: 'userRegions', value })

  renderForm() {
    const { user, localize, regionTree, navigateBack, activityTree } = this.props
    return (
      <Form className={styles.form} onSubmit={this.handleSubmit}>
        <h2>{localize('EditUser')}</h2>
        <Form.Input
          value={user.name}
          onChange={this.handleEdit}
          name="name"
          label={localize('UserName')}
          placeholder={localize('RobertDiggs')}
          required
        />
        <Form.Input
          value={user.login}
          onChange={this.handleEdit}
          name="login"
          label={localize('UserLogin')}
          placeholder={localize('LoginPlaceholder')}
          required
        />
        <Form.Input
          value={user.email}
          onChange={this.handleEdit}
          name="email"
          type="email"
          label={localize('UserEmail')}
          placeholder={localize('EmailPlaceholder')}
          required
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
          value={user.phone}
          onChange={this.handleEdit}
          name="phone"
          type="tel"
          label={localize('UserPhone')}
          placeholder="555123456"
        />
        {this.state.fetchingRoles ? (
          <Loader active />
        ) : (
          <Form.Select
            value={user.assignedRole}
            onChange={this.handleEdit}
            options={this.state.rolesList.map(r => ({ value: r.name, text: r.name }))}
            name="assignedRole"
            label={localize('AssignedRoles')}
            placeholder={localize('SelectOrSearchRoles')}
            search
          />
        )}
        {activityTree && user.assignedRole !== roles.admin &&
        <ActivityTree
          name="activiyCategoryIds"
          label="ActivityCategoryLookup"
          dataTree={activityTree}
          checked={user.activiyCategoryIds}
          callBack={this.setActivities}
          localize={localize}
          loadNode={this.props.fetchActivityTree}
        /> }
        {regionTree && user.assignedRole !== roles.admin && (
          <RegionTree
            name="RegionTree"
            label="Regions"
            dataTree={regionTree}
            checked={user.userRegions}
            callBack={this.handleCheck}
            localize={localize}
          />
        )}
        <Form.Input
          value={user.description}
          onChange={this.handleEdit}
          name="description"
          label={localize('Description')}
          placeholder={localize('NSO_Employee')}
        />
        <Button
          content={localize('Back')}
          onClick={navigateBack}
          icon={<Icon size="large" name="chevron left" />}
          size="small"
          color="grey"
          type="button"
        />
        <Button content={localize('Submit')} floated="right" type="submit" primary />
        {this.state.rolesFailMessage && (
          <div>
            <Message content={this.state.rolesFailMessage} negative />
            <Button
              onClick={() => {
                this.fetchRoles()
              }}
              type="button"
            >
              {localize('TryReloadRoles')}
            </Button>
          </div>
        )}
      </Form>
    )
  }

  render() {
    return (
      <div className={styles.userEdit}>
        {this.props.user !== undefined ? this.renderForm() : <Loader active />}
      </div>
    )
  }
}

export default Edit
