import React from 'react'
import { func, shape, oneOfType, number, string, arrayOf, object, bool } from 'prop-types'
import { Button, Form, Loader, Message, Icon, Popup } from 'semantic-ui-react'
import { equals } from 'ramda'

import ActivityTree from 'components/ActivityTree'
import RegionTree from 'components/RegionTree'
import { roles, userStatuses } from 'helpers/enums'
import { internalRequest } from 'helpers/request'
import { hasValue } from 'helpers/validation'
import styles from './styles.pcss'

class Edit extends React.Component {
  static propTypes = {
    id: oneOfType([number, string]).isRequired,
    user: shape({}),
    fetchUser: func.isRequired,
    fetchRegionTree: func.isRequired,
    editForm: func.isRequired,
    submitUser: func.isRequired,
    localize: func.isRequired,
    navigateBack: func.isRequired,
    regionTree: shape({}),
    activityTree: arrayOf(shape({})).isRequired,
    fetchActivityTree: func.isRequired,
    checkExistLogin: func.isRequired,
    loginError: oneOfType([bool, object]),
    checkExistLoginSuccess: func.isRequired,
  }
  static defaultProps = {
    regionTree: undefined,
    user: undefined,
  }

  state = {
    rolesList: [],
    fetchingRoles: true,
    rolesFailMessage: undefined,
    spinner: false,
  }

  componentDidMount() {
    this.props.checkExistLoginSuccess(false)
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

  setActivities = (activities) => {
    this.props.editForm({ name: 'activityCategoryIds', value: activities.filter(x => x !== 'all') })
    this.props.editForm({
      name: 'isAllActivitiesSelected',
      value: activities.some(x => x === 'all'),
    })
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

  checkExistLogin = (e) => {
    const loginName = e.target.value
    if (loginName.length > 0) this.props.checkExistLogin(loginName)
  }

  handleEdit = (e, { name, value }) => {
    this.props.editForm({ name, value })
  }

  handleSubmit = (e) => {
    e.preventDefault()
    this.setState({ spinner: true })
    this.props.submitUser(this.props.user)
  }

  handleCheck = value => this.props.editForm({ name: 'userRegions', value })

  renderForm() {
    const { user, localize, regionTree, navigateBack, activityTree, loginError } = this.props
    const { spinner } = this.state
    return (
      <Form className={styles.form} onSubmit={this.handleSubmit}>
        <h2>{localize('EditUser')}</h2>
        <Form.Input
          value={user.name}
          onChange={this.handleEdit}
          name="name"
          label={localize('UserName')}
          disabled={spinner}
          placeholder={localize('RobertDiggs')}
          autoComplete="off"
          maxLength={64}
          required
        />
        <Form.Input
          value={user.login}
          onChange={this.handleEdit}
          onBlur={this.checkExistLogin}
          name="login"
          label={localize('UserLogin')}
          disabled={spinner}
          placeholder={localize('LoginPlaceholder')}
          autoComplete="off"
          required
        />
        {loginError && (
          <Message size="small" visible error>
            {localize('LoginError')}
          </Message>
        )}
        <Form.Input
          value={user.email}
          onChange={this.handleEdit}
          name="email"
          type="email"
          label={localize('UserEmail')}
          disabled={spinner}
          placeholder={localize('EmailPlaceholder')}
          autoComplete="off"
          required
        />
        <Popup
          trigger={
            <Form.Input
              value={user.newPassword || ''}
              onChange={this.handleEdit}
              name="newPassword"
              type="password"
              label={localize('UsersNewPassword')}
              disabled={spinner}
              placeholder={localize('TypeStrongPasswordHere')}
              autoComplete="off"
            />
          }
          content={localize('PasswordLengthRestriction')}
          open={hasValue(user.newPassword) && user.newPassword.length < 6}
        />
        <Popup
          trigger={
            <Form.Input
              value={user.confirmPassword || ''}
              onChange={this.handleEdit}
              name="confirmPassword"
              type="password"
              label={localize('ConfirmPassword')}
              disabled={spinner}
              placeholder={localize('TypeNewPasswordAgain')}
              error={user.confirmPassword !== user.newPassword}
              autoComplete="off"
            />
          }
          content={localize('PasswordLengthRestriction')}
          open={hasValue(user.confirmPassword) && user.confirmPassword.length < 6}
        />
        <Form.Input
          value={user.phone}
          onChange={this.handleEdit}
          name="phone"
          type="number"
          disabled={spinner}
          label={localize('UserPhone')}
          placeholder="555123456"
          autoComplete="off"
        />
        {this.state.fetchingRoles ? (
          <Loader active />
        ) : (
          <Form.Select
            value={user.assignedRole}
            onChange={this.handleEdit}
            options={this.state.rolesList.map(r => ({ value: r.name, text: localize(r.name) }))}
            name="assignedRole"
            disabled={spinner}
            label={localize('AssignedRoles')}
            placeholder={localize('SelectOrSearchRoles')}
            autoComplete="off"
            search
          />
        )}
        <Form.Select
          name="status"
          value={user.status}
          onChange={this.handleEdit}
          options={[...userStatuses].map(([k, v]) => ({ value: k, text: localize(v) }))}
          disabled={spinner}
          label={localize('UserStatus')}
          autoComplete="off"
        />
        {activityTree && user.assignedRole !== roles.admin && (
          <ActivityTree
            name="activityCategoryIds"
            label="ActivityCategoryLookup"
            dataTree={activityTree}
            checked={user.activityCategoryIds}
            callBack={this.setActivities}
            disabled={spinner}
            localize={localize}
            loadNode={this.props.fetchActivityTree}
          />
        )}
        {regionTree && user.assignedRole !== roles.admin && (
          <RegionTree
            name="RegionTree"
            label="Regions"
            dataTree={regionTree}
            checked={user.userRegions}
            callBack={this.handleCheck}
            disabled={spinner}
            localize={localize}
          />
        )}
        <Form.Input
          value={user.description}
          onChange={this.handleEdit}
          name="description"
          label={localize('Description')}
          disabled={spinner}
          placeholder={localize('NSO_Employee')}
          maxLength={64}
          autoComplete="off"
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
          disabled={spinner}
          floated="right"
          type="submit"
          primary
        />
        <div className="submitUserLoader">{spinner && <Loader inline active size="small" />}</div>
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
