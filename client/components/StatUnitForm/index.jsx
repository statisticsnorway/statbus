import React from 'react'
import PropTypes from 'prop-types'
import { Formik } from 'formik'

import SubForm from './SubForm'

const SchemaFormFactory = ({
  values,
  fieldsMeta,
  dataAccess,
  schema: validationSchema,
  onSubmit: handleSubmit,
  onCancel: handleCancel,
  localize,
}) => {
  const SchemaForm = Formik({
    mapPropsToValues: props => props.values,
    validationSchema,
    handleSubmit,
  })(SubForm)
  return (
    <SchemaForm
      values={values}
      fieldsMeta={fieldsMeta}
      dataAccess={dataAccess}
      handleCancel={handleCancel}
      localize={localize}
    />
  )
}

const { arrayOf, func, string, shape } = PropTypes
SchemaFormFactory.propTypes = {
  values: shape({}).isRequired,
  fieldsMeta: shape({}).isRequired,
  dataAccess: arrayOf(string).isRequired,
  schema: shape({}).isRequired,
  onSubmit: func.isRequired,
  onCancel: func.isRequired,
  localize: func.isRequired,
}

export default SchemaFormFactory
