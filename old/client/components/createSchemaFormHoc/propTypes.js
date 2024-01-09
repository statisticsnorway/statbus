import { shape, bool, func, string, oneOfType, arrayOf, objectOf } from 'prop-types'

import { shapeOf } from '/helpers/validation'

const fieldsOf = shapeOf([])
export const subForm = {
  values: shape({}).isRequired,
  status: shape({
    errors: fieldsOf(oneOfType([string, arrayOf(string)])),
  }),
  touched: fieldsOf(oneOfType([bool, shapeOf([])])).isRequired,
  errors: fieldsOf(string).isRequired,
  dirty: bool.isRequired,
  isValid: bool.isRequired,
  isSubmitting: bool.isRequired,
  setFieldValue: func.isRequired,
  handleChange: func.isRequired,
  handleBlur: func.isRequired,
  handleSubmit: func.isRequired,
  handleReset: func.isRequired,
  localize: func.isRequired,
  locale: string.isRequired,
}

export const formBody = {
  values: shape({}).isRequired,
  getFieldErrors: func.isRequired,
  touched: objectOf(bool).isRequired,
  isSubmitting: bool.isRequired,
  setFieldValue: func.isRequired,
  setValues: func.isRequired,
  handleChange: func.isRequired,
  handleBlur: func.isRequired,
  localize: func.isRequired,
  locale: string.isRequired,
}
