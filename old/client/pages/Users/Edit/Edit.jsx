import React, { useState, useEffect } from 'react'
import { func, shape, oneOfType, number, string, arrayOf, object, bool } from 'prop-types'
import { Button, Form, Loader, Message, Icon, Popup } from 'semantic-ui-react'
import { equals } from 'ramda'

import ActivityTree from '/components/ActivityTree'
import RegionTree from '/components/RegionTree'
import { roles, userStatuses } from '/helpers/enums'
import { internalRequest } from '/helpers/request'
import { hasValue } from '/helpers/validation'
import styles from './styles.scss'

const Edit = ({
  id,
  user,
  fetchUser,
  fetchRegionTree,
  editForm,
  submitUser,
  localize,
  navigateBack,
  regionTree,
  activityTree,
  fetchActivityTree,
  checkExistLogin,
  loginError,
  checkExistLoginSuccess,
}) => {
  const [rolesList, setRolesList] = useState([])
  const [fetchingRoles, setFetchingRoles] = useState(true)
  const [rolesFailMessage, setRolesFailMessage] = useState(undefined)
  const [spinner, setSpinner] = useState(false)

  useEffect(() => {
    checkExistLoginSuccess(false)
    fetchRegionTree()
    fetchUser(id)
    fetchRoles()
    fetchActivityTree()
  }, [id])

  useEffect(() => {
    setRolesFailMessage(undefined)
  }, [fetchingRoles])

  const setActivities = (activities) => {
    editForm({ name: 'activityCategoryIds', value: activities.filter(x => x !== 'all') })
    editForm({ name: 'isAllActivitiesSelected', value: activities.some(x => x === 'all') })
  }

  const fetchRoles = () => {
    internalRequest({
      url: '/api/roles',
      onSuccess: ({ result }) => {
        setRolesList(result)
        setFetchingRoles(false)
      },
      onFail: () => {
        setRolesFailMessage('failed loading roles')
        setFetchingRoles(false)
      },
    })
  }

  const checkExistLoginHandler = (e) => {
    const loginName = e.target.value
    if (loginName.length > 0) checkExistLogin(loginName)
  }

  const handleEdit = (e, { name, value }) => {
    editForm({ name, value })
  }

  const handleSubmit = (e) => {
    e.preventDefault()
    setSpinner(true)
    submitUser(user)
  }

  const handleCheck = (value) => {
    editForm({ name: 'userRegions', value })
  }

  const renderForm = () => (
    <Form className={styles.form} onSubmit={handleSubmit}>
      <h2>{localize('EditUser')}</h2>
      <Form.Input
        value={user.name}
        onChange={handleEdit}
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
        onChange={handleEdit}
        onBlur={checkExistLoginHandler}
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
        onChange={handleEdit}
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
            onChange={handleEdit}
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
            onChange={handleEdit}
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
        onChange={handleEdit}
        name="phone"
        type="number"
        disabled={spinner}
        label={localize('UserPhone')}
        placeholder="555123456"
        autoComplete="off"
      />
      {fetchingRoles ? (
        <Loader active />
        ) : (
          <Form.Select
            value={user.assignedRole}
            onChange={handleEdit}
            options={rolesList.map(r => ({ value: r.name, text: localize(r.name) }))}
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
        onChange={handleEdit}
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
        callBack={setActivities}
        disabled={spinner}
        localize={localize}
        loadNode={fetchActivityTree}
      />
        )}
      {regionTree && user.assignedRole !== roles.admin && (
      <RegionTree
        name="RegionTree"
        label="Regions"
        dataTree={regionTree}
        checked={user.userRegions}
        callBack={handleCheck}
        disabled={spinner}
        localize={localize}
      />
        )}
      <Form.Input
        value={user.description}
        onChange={handleEdit}
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
      {rolesFailMessage && (
      <div>
        <Message content={rolesFailMessage} negative />
        <Button
          onClick={() => {
                fetchRoles()
              }}
          type="button"
        >
          {localize('TryReloadRoles')}
        </Button>
      </div>
        )}
    </Form>
  )

  return (
    <div className={styles.userEdit}>{user !== undefined ? renderForm() : <Loader active />}</div>
  )
}

Edit.propTypes = {
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

Edit.defaultProps = {
  regionTree: undefined,
  user: undefined,
}

export default Edit
