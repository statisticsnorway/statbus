import React from 'react'
import PropTypes from 'prop-types'
import { Segment, Select } from 'semantic-ui-react'

import { bodyPropTypes } from 'helpers/formik'
import PlainTextField from 'components/fields/TextField'
import withDebounce from 'components/fields/withDebounce'
import { meta } from './model'

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
  const createProps = (key) => {
    const props = {
      ...meta.get(key),
      name: key,
      value: values[key],
      touched: !!touched[key],
      errors: getFieldErrors(key),
      disabled: isSubmitting,
      setFieldValue,
      onBlur: handleBlur,
      localize,
    }
    if (props.options) {
      props.options = meta.get(key).options.map(x => ({ ...x, text: localize(x.text) }))
    }
    return props
  }
  const attributeOptions = values.attributesToCheck.map(x => ({ value: x, text: localize(x) }))
  return (
    <Segment>
      <TextField {...createProps(meta.get('name'))} />
      <TextField {...createProps(meta.get('description'))} />
      <Select {...createProps(meta.get('allowedOperations'))} />
      <Select {...createProps(meta.get('priority'))} />
      <Select {...createProps(meta.get('statUnitType'))} />
    </Segment>
  )
}

const { arrayOf, shape, string, number } = PropTypes
FormBody.propTypes = {
  ...bodyPropTypes,
  values: shape({
    name: string.isRequired,
    description: string.isRequired,
    allowedOperations: number.isRequired,
    priority: number.isRequired,
    statUnitType: number.isRequired,
    attributesToCheck: arrayOf(string).isRequired,
    variablesMapping: arrayOf(arrayOf(string)).isRequired,
  }).isRequired,
}

export default FormBody
