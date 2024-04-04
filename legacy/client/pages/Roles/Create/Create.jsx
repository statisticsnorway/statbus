import React, { useState, useEffect } from 'react'
import PropTypes from 'prop-types'
import { Button, Form, Icon, Loader } from 'semantic-ui-react'
import { equals } from 'ramda'

import FunctionalAttributes from '/components/FunctionalAttributes'
import DataAccess from '/components/DataAccess'
import ActivityTree from '/components/ActivityTree'
import { internalRequest } from '/helpers/request'
import styles from './styles.scss'

function CreateForm({ localize, submitRole, navigateBack }) {
  const [data, setData] = useState({
    name: '',
    description: '',
    accessToSystemFunctions: [],
    standardDataAccess: {
      localUnit: [],
      legalUnit: [],
      enterpriseGroup: [],
      enterpriseUnit: [],
    },
    activityCategoryIds: [],
  })

  const [activityTree, setActivityTree] = useState(undefined)
  const [fetchingStandardDataAccess, setFetchingStandardDataAccess] = useState(true)

  useEffect(() => {
    fetchActivityTree()
    fetchStandardDataAccess()
  }, [])

  const setActivities = (activities) => {
    setData(prevData => ({
      ...prevData,
      activityCategoryIds: activities.filter(x => x !== 'all'),
    }))
  }

  const fetchStandardDataAccess = () => {
    internalRequest({
      url: '/api/accessAttributes/dataAttributes',
      onSuccess: (result) => {
        setData(prevData => ({
          ...prevData,
          standardDataAccess: result,
        }))
        setFetchingStandardDataAccess(false)
      },
      onFail: () => {
        setFetchingStandardDataAccess(false)
      },
    })
  }

  const fetchActivityTree = () => {
    internalRequest({
      url: '/api/roles/fetchActivityTree',
      onSuccess: (activityTree) => {
        setActivityTree(activityTree)
      },
    })
  }

  const handleAccessToSystemFunctionsChange = (data) => {
    setData(prevData => ({
      ...prevData,
      [data.name]: data.checked
        ? [...prevData.accessToSystemFunctions, data.value]
        : prevData.accessToSystemFunctions.filter(x => x !== data.value),
    }))
  }

  const handleEdit = (e, { name, value }) => {
    setData(prevData => ({
      ...prevData,
      [name]: value,
    }))
  }

  const handleSubmit = (e) => {
    e.preventDefault()
    submitRole(data)
  }

  return (
    <div className={styles.rolecreate}>
      <Form className={styles.form} onSubmit={handleSubmit}>
        <h2>{localize('CreateNewRole')}</h2>
        <Form.Input
          name="name"
          onChange={handleEdit}
          value={data.name}
          label={localize('RoleName')}
          placeholder={localize('RoleNamePlaceholder')}
          required
        />
        <Form.Input
          name="description"
          onChange={handleEdit}
          value={data.description}
          label={localize('Description')}
          placeholder={localize('RoleDescriptionPlaceholder')}
          required
        />
        {fetchingStandardDataAccess ? (
          <Loader />
        ) : (
          <DataAccess
            value={data.standardDataAccess}
            name="standardDataAccess"
            label={localize('DataAccess')}
            onChange={handleEdit}
            localize={localize}
          />
        )}
        {activityTree && (
          <ActivityTree
            name="activityCategoryIds"
            label="ActivityCategoryLookup"
            dataTree={activityTree}
            checked={data.activityCategoryIds}
            callBack={setActivities}
            localize={localize}
          />
        )}
        <FunctionalAttributes
          label={localize('AccessToSystemFunctions')}
          value={data.accessToSystemFunctions}
          onChange={handleAccessToSystemFunctionsChange}
          name="accessToSystemFunctions"
          localize={localize}
        />
        <Button
          content={localize('Back')}
          onClick={navigateBack}
          icon={<Icon size="large" name="chevron left" />}
          size="small"
          color="grey"
          type="button"
        />
        <Button className={styles.sybbtn} type="submit" primary>
          {localize('Submit')}
        </Button>
      </Form>
    </div>
  )
}

CreateForm.propTypes = {
  localize: PropTypes.func.isRequired,
  submitRole: PropTypes.func.isRequired,
  navigateBack: PropTypes.func.isRequired,
}

export default CreateForm
