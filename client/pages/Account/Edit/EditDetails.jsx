import React from 'react'
import PropTypes from 'prop-types'

import { shapeOf } from 'helpers/formik'
import createSchemaForm from 'components/createSchemaForm'
import { schema, names } from './model'
import FormBody from './FormBody'
import styles from './styles.pcss'

const SchemaForm = createSchemaForm(schema)(FormBody)

const EditDetails = ({ formData, submitAccount, navigateBack, localize }) => (
  <div>
    <h2>{localize('EditAccount')}</h2>
    <div className={styles.accountEdit}>
      <SchemaForm
        values={formData}
        onSubmit={submitAccount}
        onCancel={navigateBack}
        localize={localize}
      />
    </div>
  </div>
)

const { func, string } = PropTypes
EditDetails.propTypes = {
  formData: shapeOf(names)(string).isRequired,
  submitAccount: func.isRequired,
  navigateBack: func.isRequired,
  localize: func.isRequired,
}

export default EditDetails
