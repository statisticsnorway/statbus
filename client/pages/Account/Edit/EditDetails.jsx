import React from 'react'
import PropTypes from 'prop-types'

import { shapeOf } from 'helpers/formik'
import createFormHoc from 'components/createFormHoc'
import { names } from './model'
import FormBody from './FormBody'
import schema from './schema'
import styles from './styles.pcss'

const EditDetails = ({ formData, submitAccount, onCancel, localize }) => {
  const Form = createFormHoc({
    schema,
    mapPropsToValues: props => props.formData,
    onSubmit: (values, formikBag) => {
      submitAccount(values, formikBag)
    },
    onCancel,
    localize,
  })(FormBody)

  return (
    <div>
      <h2>{localize('EditAccount')}</h2>
      <div className={styles.accountEdit}>
        <Form formData={formData} />
      </div>
    </div>
  )
}

const { func, string } = PropTypes
EditDetails.propTypes = {
  formData: shapeOf(names)(string).isRequired,
  submitAccount: func.isRequired,
  onCancel: func.isRequired,
  localize: func.isRequired,
}

export default EditDetails
