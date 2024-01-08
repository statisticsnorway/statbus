import React from 'react'
import PropTypes from 'prop-types'
import { Segment } from 'semantic-ui-react'

import { TextField as PlainTextField, withDebounce } from '/components/fields'
import { formBody as bodyPropTypes } from '/components/createSchemaFormHoc/propTypes'
import handlerFor from '/helpers/handleSetFieldValue'
import { shapeOf } from '/helpers/validation'
import { meta } from './model.js'

const TextField = withDebounce(PlainTextField)
const names = [...meta.keys()]

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
    onChange: handlerFor(setFieldValue),
    onBlur: handleBlur,
    localize,
  })
  return (
    <Segment>
      {names.map(key => (
        <TextField key={key} {...createProps(key)} />
      ))}
    </Segment>
  )
}

const { string } = PropTypes
FormBody.propTypes = {
  ...bodyPropTypes,
  values: shapeOf(names)(string).isRequired,
}

export default FormBody
