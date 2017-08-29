import React from 'react'
import PropTypes from 'prop-types'
import { Formik } from 'formik'

import SubForm from './SubForm'

const SchemaFormFactory = ({
  values,
  fieldsMeta,
  schema: validationSchema,
  onSubmit: handleSubmit,
  onCancel: handleCancel,
  localize,
}) => {
  const SchemaForm = Formik({
    mapPropsToValues: props => props.values, // eslint-disable-line react/prop-types
    validationSchema,
    handleSubmit,
  })(SubForm)
  return (
    <SchemaForm
      values={values}
      fieldsMeta={fieldsMeta}
      handleCancel={handleCancel}
      localize={localize}
    />
  )
}

const { func, shape } = PropTypes
SchemaFormFactory.propTypes = {
  values: shape({}).isRequired,
  fieldsMeta: shape({}).isRequired,
  schema: shape({}).isRequired,
  onSubmit: func.isRequired,
  onCancel: func.isRequired,
  localize: func.isRequired,
}

export default SchemaFormFactory
