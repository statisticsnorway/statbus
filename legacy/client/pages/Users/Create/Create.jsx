import React, { useState, useEffect } from 'react'
import { func, oneOfType, bool, object } from 'prop-types'
import { Button, Form, Loader, Message, Icon, Popup } from 'semantic-ui-react'
import { equals } from 'ramda'

import ActivityTree from '/components/ActivityTree'
import RegionTree from '/components/RegionTree'
import { internalRequest } from '/helpers/request'
import { userStatuses, roles } from '/helpers/enums'
import { distinctBy } from '/helpers/enumerable'
import { hasValue } from '/helpers/validation'
import styles from './styles.scss'

const Create = ({
  localize,
  submitUser,
  navigateBack,
  checkExistLogin,
  loginError,
  checkExistLoginSuccess,
}) => {
  const [data, setData] = useState({
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
    activityCategoryIds: [],
  })

  const [regionTree, setRegionTree] = useState(undefined)
  const [rolesList, setRolesList] = useState([])
  const [fetchingRoles, setFetchingRoles] = useState(true)
  const [fetchingRegions, setFetchingRegions] = useState(true)
  const [fetchingActivities, setFetchingActivities] = useState(true)
  const [rolesFailMessage, setRolesFailMessage] = useState(undefined)
  const [activityTree, setActivityTree] = useState([])
  const [spinner, setSpinner] = useState(false)

  useEffect(() => {
    checkExistLoginSuccess(false)
    fetchRegionTree()
    fetchRoles()
    fetchActivityTree()
  }, [])

  useEffect(() => {
    setRolesFailMessage(undefined)
  }, [fetchingRoles, fetchingRegions, fetchingActivities])

  const setActivities = (activities) => {
    setData(prevData => ({
      ...prevData,
      activityCategoryIds: activities.filter(x => x !== 'all'),
      isAllActivitiesSelected: activities.some(x => x === 'all'),
    }))
  }

  const fetchRegionTree = () => {
    internalRequest({
      url: '/api/Regions/GetAllRegionTree',
      method: 'get',
      onSuccess: (result) => {
        setRegionTree(result)
        setFetchingRegions(false)
      },
      onFail: () => {
        setRolesFailMessage('failed loading regions')
        setFetchingRegions(false)
      },
    })
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

  const fetchActivityTree = (parentId = 0) => {
    internalRequest({
      url: `/api/roles/fetchActivityTree?parentId=${parentId}`,
      onSuccess: (result) => {
        setActivityTree(prevActivityTree => distinctBy([...prevActivityTree, ...result], x => x.id))
        setFetchingActivities(false)
      },
      onFail: () => {
        setRolesFailMessage('failed loading activities')
        setFetchingActivities(false)
      },
    })
  }

  const handleEdit = (e, { name, value }) => {
    setData(prevData => ({ ...prevData, [name]: value }))
  }

  const checkExistLoginHandler = (e) => {
    const loginName = e.target.value
    if (loginName.length > 0) checkExistLogin(loginName)
  }

  const handleSubmit = (e) => {
    e.preventDefault()
    setSpinner(true)
    submitUser(data)
  }

  const handleCheck = value => handleEdit(null, { name: 'userRegions', value })

  return (
    <div className={styles.root}>
      <Form onSubmit={handleSubmit}>
        <h2>{localize('CreateNewUser')}</h2>
        <Form.Input
          name="name"
          value={data.name}
          onChange={handleEdit}
          label={localize('UserName')}
          disabled={spinner}
          maxLength={64}
          placeholder="e.g. Robert Diggs"
          autoComplete="off"
          required
        />
        <Form.Input
          name="login"
          value={data.login}
          onChange={handleEdit}
          onBlur={checkExistLoginHandler}
          label={localize('UserLogin')}
          disabled={spinner}
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
          onChange={handleEdit}
          type="email"
          label={localize('UserEmail')}
          disabled={spinner}
          placeholder="e.g. robertdiggs@site.domain"
          autoComplete="off"
          required
        />
        <Popup
          trigger={
            <Form.Input
              name="password"
              value={data.password}
              onChange={handleEdit}
              type="password"
              label={localize('UserPassword')}
              disabled={spinner}
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
              onChange={handleEdit}
              type="password"
              label={localize('ConfirmPassword')}
              disabled={spinner}
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
          onChange={handleEdit}
          type="number"
          label={localize('UserPhone')}
          disabled={spinner}
          placeholder="555123456"
          autoComplete="off"
        />
        {fetchingRoles ? (
          <Loader content="fetching roles" active />
        ) : (
          <Form.Select
            name="assignedRole"
            value={data.assignedRole}
            onChange={handleEdit}
            options={rolesList.map(r => ({ value: r.name, text: localize(r.name) }))}
            label={localize('AssignedRoles')}
            disabled={spinner}
            placeholder={localize('SelectOrSearchRoles')}
            autoComplete="off"
            search
          />
        )}
        <Form.Select
          name="status"
          value={data.status}
          onChange={handleEdit}
          options={[...userStatuses].map(([k, v]) => ({ value: k, text: localize(v) }))}
          autoComplete="off"
          disabled={spinner}
          label={localize('UserStatus')}
        />
        {!fetchingRoles && data.assignedRole !== roles.admin && (
          <ActivityTree
            name="activiyCategoryIds"
            label="ActivityCategoryLookup"
            dataTree={activityTree}
            loaded={!fetchingActivities}
            checked={data.activiyCategoryIds}
            callBack={setActivities}
            disabled={spinner}
            localize={localize}
            loadNode={fetchActivityTree}
          />
        )}
        {!fetchingRoles && data.assignedRole !== roles.admin && (
          <RegionTree
            name="RegionTree"
            label="Regions"
            loaded={!fetchingRegions}
            dataTree={regionTree}
            checked={data.userRegions}
            callBack={handleCheck}
            disabled={spinner}
            localize={localize}
          />
        )}
        <Form.Input
          name="description"
          value={data.description}
          onChange={handleEdit}
          label={localize('Description')}
          disabled={spinner}
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
          disabled={fetchingRoles || fetchingActivities || fetchingRegions || loginError || spinner}
          floated="right"
          primary
        />
        <div className="submitUserLoader">{spinner && <Loader inline active size="small" />}</div>
        {rolesFailMessage && (
          <div>
            <Message content={rolesFailMessage} negative />
            <Button onClick={fetchRoles} type="button">
              {localize('TryReloadRoles')}
            </Button>
          </div>
        )}
      </Form>
    </div>
  )
}

Create.propTypes = {
  localize: func.isRequired,
  submitUser: func.isRequired,
  navigateBack: func.isRequired,
  checkExistLogin: func.isRequired,
  loginError: oneOfType([bool, object]),
  checkExistLoginSuccess: func.isRequired,
}

export default Create
