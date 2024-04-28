import React from 'react'
import { arrayOf, bool, func, number, oneOfType, string } from 'prop-types'
import { Message, Form } from 'semantic-ui-react'

import { hasValue } from '/helpers/validation'

export function NumberField({
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
}) {
  const label = labelKey !== undefined ? localize(labelKey) : undefined
  const title = titleKey ? localize(titleKey) : label
  const hasErrors = touched !== false && hasValue(errorKeys)

  const handleInputChange = (event, { value: nextValue, ...data }) => {
    onChange(event, { ...data, value: hasValue(nextValue) ? nextValue : null })
  }

  return (
    <div
      className="field"
      data-tooltip={popuplocalizedKey ? localize(popuplocalizedKey) : null}
      data-position="top left"
    >
      <Form.Input
        {...restProps}
        value={value != null ? value : ''}
        onChange={handleInputChange}
        error={error || hasErrors}
        type={type}
        label={label}
        title={title}
        placeholder={placeholderKey ? localize(placeholderKey) : label}
        autoComplete="off"
      />
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
