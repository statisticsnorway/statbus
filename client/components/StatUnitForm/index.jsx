import React from 'react'
import { Formik } from 'formik'

import SubForm from './SubForm'

// TODO try using reselect to avoid recalculation of props (current mapPropsToValues approach)
// =====================================
const withLifecycleLogs = require('recompose').lifecycle({
  componentDidMount() { console.warn(this.constructor.displayName, 'MOUNTED!') },
  componentWillUnmount() { console.warn(this.constructor.displayName, 'UNMOUNTING...') },
})
// =====================================

const SchemaFormFactory = ({
  values,
  schema,
  fieldsMeta,
  onSubmit,
  onCancel,
  localize,
  ...rest
}) => {
  // TODO: revise schema and values creation
  const withFormik = Formik({
    ...rest,
    mapPropsToValues: props => props.values,
    validationSchema: schema,
    handleSubmit: onSubmit,
  })
  const SchemaForm = withLifecycleLogs(withFormik(SubForm))
  return (
    <SchemaForm
      values={values}
      fieldsMeta={fieldsMeta}
      handleCancel={onCancel}
      localize={localize}
    />
  )
}

export default SchemaFormFactory
