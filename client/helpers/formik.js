import { shape, bool, func, string, oneOfType, arrayOf, objectOf } from 'prop-types'
import { pathOr } from 'ramda'

import { ensureArray } from 'helpers/schema'

export const shapeOf = fields =>
  propType =>
    shape(fields.reduce((acc, curr) => ({ ...acc, [curr]: propType }), {}))

export const bodyPropTypes = ({
  values: shape({}).isRequired,
  getFieldErrors: func.isRequired,
  touched: objectOf(bool).isRequired,
  isSubmitting: bool.isRequired,
  setFieldValue: func.isRequired,
  setValues: func.isRequired,
  handleChange: func.isRequired,
  handleBlur: func.isRequired,
  localize: func.isRequired,
})

export const createBasePropTypes = (fields) => {
  const fieldsOf = shapeOf(fields)
  return {
    values: shape({}).isRequired,
    status: shape({
      errors: fieldsOf(oneOfType([string, arrayOf(string)])),
    }),
    touched: fieldsOf(bool).isRequired,
    errors: fieldsOf(string).isRequired,
    dirty: bool.isRequired,
    isValid: bool.isRequired,
    isSubmitting: bool.isRequired,
    setFieldValue: func.isRequired,
    handleChange: func.isRequired,
    handleBlur: func.isRequired,
    handleSubmit: func.isRequired,
    handleReset: func.isRequired,
    handleCancel: func.isRequired,
    localize: func.isRequired,
  }
}

export const collectErrors = (errors, statusErrors) => key =>
  [...ensureArray(errors[key]), ...pathOr([], [key], statusErrors)]
