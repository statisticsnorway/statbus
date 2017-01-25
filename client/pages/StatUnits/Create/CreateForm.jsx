import React from 'react'
import { Button, Form } from 'semantic-ui-react'

import statUnitTypes from 'helpers/statUnitTypes'
import { format } from 'helpers/dateHelper'
import { wrapper } from 'helpers/locale'
import styles from './styles.pcss'
import CreateStatUnit from './CreateStatUnit'
import CreateEnterpriseGroup from './CreateEnterpriseGroup'

const CreateForm = ({ handleSubmit, localize, editForm, statUnit,
  legalUnitOptions, enterpriseUnitOptions, enterpriseGroupOptions }) => {
  const handleEdit = propName => e => editForm({ propName, value: e.target.value })
  const handleDateEdit = propName => ({ _d: date }) =>
    editForm({ propName, value: format(date) })
  const handleSelectEdit = (e, { name, value }) => editForm({ propName: name, value })
  const statUnitTypeOptions =
    [...statUnitTypes].map(([key, value]) => ({ value: key, text: value }))
  const props = {
    statUnit,
    handleEdit,
    handleDateEdit,
    handleSelectEdit,
    statUnitTypeOptions,
    legalUnitOptions,
    enterpriseUnitOptions,
    enterpriseGroupOptions,
  }
  return (
    <div className={styles.edit}>
      <Form className={styles.form} onSubmit={handleSubmit}>
        { statUnit.type == 4 ? <CreateEnterpriseGroup {...props} /> : <CreateStatUnit {...props} /> }
        <br />
        <Button className={styles.sybbtn} type="submit" primary>{localize('Submit')}</Button>
      </Form>
    </div>
  )
}

CreateForm.propTypes = {}

export default wrapper(CreateForm)
