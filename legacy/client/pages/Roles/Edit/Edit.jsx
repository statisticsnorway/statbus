import React, { useEffect } from 'react'
import PropTypes from 'prop-types'
import { Button, Form, Loader, Icon } from 'semantic-ui-react'
import { equals } from 'ramda'

import DataAccess from '/components/DataAccess'
import { roles } from '/helpers/enums'
import styles from './styles.scss'

function Edit({ id, activityTree, role, editForm, fetchRole, submitRole, navigateBack, localize }) {
  useEffect(() => {
    fetchRole(id)
  }, [id, fetchRole])

  const setRegion = (region) => {
    editForm({ name: 'region', value: region })
  }

  const setActivities = (activities) => {
    editForm({ name: 'activityCategoryIds', value: activities.filter(x => x !== 'all') })
  }

  const handleEdit = (e, { name, value }) => {
    editForm({ name, value })
  }

  const handleSubmit = (e) => {
    e.preventDefault()
    submitRole({ ...role })
  }

  const handleAccessToSystemFunctionsChange = e =>
    editForm({
      name: e.name,
      value: e.checked
        ? [...role.accessToSystemFunctions, e.value]
        : role.accessToSystemFunctions.filter(x => x !== e.value),
    })

  return (
    <div className={styles.roleEdit}>
      {role === undefined ? (
        <Loader active />
      ) : (
        <Form className={styles.form} onSubmit={handleSubmit}>
          <h2>{localize('EditRole')}</h2>
          <Form.Input
            value={localize(role.name)}
            onChange={handleEdit}
            name="name"
            label={localize('RoleName')}
            placeholder={localize('RoleNamePlaceholder')}
            required
            disabled
          />
          <Form.Input
            value={role.description}
            onChange={handleEdit}
            name="description"
            label={localize('Description')}
            placeholder={localize('RoleDescriptionPlaceholder')}
          />
          {role.name !== roles.external && (
            <Form.Input
              value={role.sqlWalletUser}
              onChange={handleEdit}
              name="sqlWalletUser"
              label={localize('SqlWalletUser')}
              placeholder={localize('SqlWalletUserPlaceholder')}
            />
          )}
          {role.name !== roles.admin && (
            <DataAccess
              value={role.standardDataAccess}
              name="standardDataAccess"
              label={localize('DataAccess')}
              onChange={handleEdit}
              localize={localize}
              readEditable={role.name === roles.employee || role.name === roles.external}
              writeEditable={role.name === roles.employee}
            />
          )}
          <Button
            content={localize('Back')}
            onClick={navigateBack}
            icon={<Icon size="large" name="chevron left" />}
            size="small"
            color="grey"
            type="button"
          />
          <Button content={localize('Submit')} className={styles.sybbtn} type="submit" primary />
        </Form>
      )}
    </div>
  )
}

Edit.propTypes = {
  id: PropTypes.oneOfType([PropTypes.number, PropTypes.string]).isRequired,
  activityTree: PropTypes.arrayOf(PropTypes.shape({})).isRequired,
  role: PropTypes.shape({}).isRequired,
  editForm: PropTypes.func.isRequired,
  fetchRole: PropTypes.func.isRequired,
  submitRole: PropTypes.func.isRequired,
  navigateBack: PropTypes.func.isRequired,
  localize: PropTypes.func.isRequired,
}

export default Edit
