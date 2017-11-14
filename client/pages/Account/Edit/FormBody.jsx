import React from 'react'
import PropTypes from 'prop-types'
import { Segment } from 'semantic-ui-react'

import { formBody as bodyPropTypes } from 'components/createSchemaFormHoc/propTypes'
import { shapeOf } from 'helpers/validation'
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
  return <Segment>{names.map(key => <TextField key={key} {...createProps(key)} />)}</Segment>
}

const { string } = PropTypes
FormBody.propTypes = {
  ...bodyPropTypes,
  values: shapeOf(names)(string).isRequired,
}

export default FormBody
