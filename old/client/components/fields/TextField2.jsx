import React from 'react'
import { arrayOf, bool, func, number, oneOfType, string } from 'prop-types'
import { Message, Form } from 'semantic-ui-react'
import { getSeparator, isAllowedValue } from 'helpers/validation.js'

export const TextField2 = ({
  value,
  field,
  operation,
  label: labelKey,
  title: titleKey,
  placeholder: placeholderKey,
  touched,
  error,
  errors: errorKeys,
  localize,
  highlighted,
  popuplocalizedKey,
  onChange,
  ...restProps
}) => {
  const label = labelKey !== undefined ? localize(labelKey) : undefined
  const title = titleKey ? localize(titleKey) : label
  const hasErrors = touched !== false && errorKeys.length !== 0
  const props = {
    ...restProps,
    value: value !== null ? value : '',
    error: error || hasErrors,
    onChange: (e, data) => {
      const separator = getSeparator(field, operation)
      if (isAllowedValue(data.value, separator) || data.value.length === 0) {
        onChange(e, data)
      }
    },
    label,
    title,
    placeholder: placeholderKey ? localize(placeholderKey) : label,
    autoComplete: 'off',
  }
  const cssClass = `field ${highlighted && touched ? 'valid-highlight' : null}`
  return (
    <div
      className={cssClass}
      data-tooltip={popuplocalizedKey ? localize(popuplocalizedKey) : null}
      data-position="top left"
    >
      {restProps.name === 'name' ? <Form.TextArea {...props} /> : <Form.Input {...props} />}
      {hasErrors && <Message title={label} list={errorKeys.map(localize)} compact error />}
    </div>
  )
}

TextField2.propTypes = {
  label: string,
  title: string,
  placeholder: string,
  value: string,
  touched: bool,
  error: bool,
  errors: arrayOf(string),
  localize: func.isRequired,
  highlighted: bool,
  popuplocalizedKey: string,
}

TextField2.defaultProps = {
  value: '',
  label: undefined,
  title: undefined,
  placeholder: undefined,
  touched: undefined,
  error: false,
  errors: [],
  highlighted: false,
  popuplocalizedKey: undefined,
}
