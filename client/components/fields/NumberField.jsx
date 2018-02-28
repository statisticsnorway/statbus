import React from 'react'
import { arrayOf, bool, func, number, oneOfType, string } from 'prop-types'
import { Message, Form } from 'semantic-ui-react'

import { hasValue } from 'helpers/validation'

const NumberField = ({
  value,
  onChange,
  label: labelKey,
  title: titleKey,
  placeholder: placeholderKey,
  touched,
  error,
  errors: errorKeys,
  type,
  localize,
  popuplocalizedKey,
  ...restProps
}) => {
  const label = labelKey !== undefined ? localize(labelKey) : undefined
  const title = titleKey ? localize(titleKey) : label
  const hasErrors = touched !== false && hasValue(errorKeys)
  const props = {
    ...restProps,
    value: value != null ? value : '',
    onChange: (event, { value: nextValue, ...data }) => {
      onChange(event, { ...data, value: hasValue(nextValue) ? nextValue : null })
    },
    error: error || hasErrors,
    type,
    label,
    title,
    placeholder: placeholderKey ? localize(placeholderKey) : label,
  }
  return popuplocalizedKey ? (
    <div className="field" data-tooltip={localize(popuplocalizedKey)} data-position="top left">
      <Form.Input {...props} />
      {hasErrors && <Message title={label} list={errorKeys.map(localize)} compact error />}
    </div>
  ) : (
    <div className="field">
      <Form.Input {...props} />
      {hasErrors && <Message title={label} list={errorKeys.map(localize)} compact error />}
    </div>
  )
}

NumberField.propTypes = {
  label: string,
  title: string,
  placeholder: string,
  value: oneOfType([string, number]),
  touched: bool,
  error: bool,
  errors: arrayOf(string),
  disabled: bool,
  type: string,
  onChange: func.isRequired,
  localize: func.isRequired,
  popuplocalizedKey: string,
}

NumberField.defaultProps = {
  value: '',
  label: undefined,
  title: undefined,
  placeholder: undefined,
  touched: undefined,
  error: false,
  errors: [],
  disabled: false,
  type: 'number',
  popuplocalizedKey: undefined,
}

export default NumberField
