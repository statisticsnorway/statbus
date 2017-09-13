import React from 'react'
import PropTypes from 'prop-types'
import { Segment } from 'semantic-ui-react'

import { shapeOf } from 'helpers/formik'
import PlainTextField from 'components/fields/TextField'
import withDebounce from 'components/fields/withDebounce'
import { meta, names } from './model'

const TextField = withDebounce(PlainTextField)

const FormBody = ({
  values,
  getFieldErrors,
  touched,
  isSubmitting,
  setFieldValue,
  handleBlur,
  localize,
}) => {
  const createProps = key => ({
    ...meta.get(key),
    name: key,
    value: values[key],
    touched: !!touched[key],
    errors: getFieldErrors(key),
    disabled: isSubmitting,
    setFieldValue,
    onBlur: handleBlur,
    localize,
  })
  return (
    <Segment>
      {names.map(key => <TextField key={key} {...createProps(key)} />)}
    </Segment>
  )
}

const { bool, func, string: string_ } = PropTypes
const modelOf = shapeOf(names)
FormBody.propTypes = {
  values: modelOf(string_).isRequired,
  getFieldErrors: func.isRequired,
  touched: modelOf(bool).isRequired,
  isSubmitting: bool.isRequired,
  setFieldValue: func.isRequired,
  handleBlur: func.isRequired,
  localize: func.isRequired,
}

export default FormBody
