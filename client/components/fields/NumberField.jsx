import React from 'react'
import { arrayOf, bool, func, number, oneOfType, string } from 'prop-types'
import { Message, Form } from 'semantic-ui-react'

import { hasValue } from 'helpers/validation'

const NumberField = ({
  name,
  value,
  label: labelKey,
  title: titleKey,
  placeholder: placeholderKey,
  touched,
  error,
  errors: errorKeys,
  type,
  setFieldValue,
  localize,
  ...restProps
}) => {
  const label = localize(labelKey)
  const title = titleKey ? localize(titleKey) : label
  const hasErrors = touched && hasValue(errorKeys)
  const props = {
    ...restProps,
    name,
    type,
    label,
    title,
    value: value != null ? value : '',
    error: error || hasErrors,
    onChange: (_, { value: nextValue }) =>
      setFieldValue(name, hasValue(nextValue) ? nextValue : null),
    placeholder: placeholderKey ? localize(placeholderKey) : label,
  }
  return (
    <div className="field">
      <Form.Input {...props} />
      {hasErrors && <Message title={label} list={errorKeys.map(localize)} compact error />}
    </div>
  )
}

NumberField.propTypes = {
  name: string.isRequired,
  label: string.isRequired,
  title: string,
  placeholder: string,
  value: oneOfType([string, number]),
  touched: bool.isRequired,
  error: bool,
  errors: arrayOf(string),
  disabled: bool,
  type: string,
  setFieldValue: func.isRequired,
  localize: func.isRequired,
}

NumberField.defaultProps = {
  value: '',
  title: undefined,
  placeholder: undefined,
  error: false,
  errors: [],
  disabled: false,
  type: 'number',
}

export default NumberField
