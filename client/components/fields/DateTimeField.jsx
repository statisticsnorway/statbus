import React from 'react'
import { bool, arrayOf, func, string } from 'prop-types'
import DatePicker from 'react-datepicker'
import { Form, Message } from 'semantic-ui-react'
import { isNil } from 'ramda'

import { getDateOrNull, toUtc, dateFormat } from 'helpers/dateHelper'
import { hasValue } from 'helpers/validation'

const asDate = x => (isNil(x) ? x : toUtc(x))

const DateTimeField = (rootProps) => {
  const {
    id: ambiguousId,
    name: ambiguousName,
    value,
    onChange,
    label: labelKey,
    title: titleKey,
    placeholder: placeholderKey,
    format,
    touched,
    error,
    required,
    errors: errorKeys,
    localize,
    ...restProps
  } = rootProps
  const hasErrors = touched !== false && hasValue(errorKeys)
  const label = labelKey !== undefined ? localize(labelKey) : undefined
  const title = titleKey ? localize(titleKey) : label
  const id =
    ambiguousId != null ? ambiguousId : ambiguousName != null ? ambiguousName : 'DateTimeField'
  const inputProps = {
    ...restProps,
    id,
    name: ambiguousName,
    value,
    title,
    dateFormat: format,
    required,
    as: DatePicker,
    selected: getDateOrNull(value),
    error: error || hasErrors,
    onChange: (ambiguousValue) => {
      const nextValue = asDate(ambiguousValue)
      onChange(
        { target: { name: ambiguousName, value: nextValue } },
        { ...rootProps, value: nextValue },
      )
    },
    placeholder: placeholderKey ? localize(placeholderKey) : label,
    className: 'ui input',
  }
  return (
    <div className={`field datepicker${required ? ' required' : ''}${hasErrors ? ' error' : ''}`}>
      {label !== undefined && <label htmlFor={id}>{label}</label>}
      <Form.Input {...inputProps} />
      {hasErrors && <Message title={label} list={errorKeys.map(localize)} compact error />}
    </div>
  )
}

DateTimeField.propTypes = {
  value: string,
  onChange: func.isRequired,
  id: string,
  name: string,
  label: string,
  title: string,
  placeholder: string,
  format: string,
  required: bool,
  touched: bool,
  error: bool,
  errors: arrayOf(string),
  localize: func.isRequired,
}

DateTimeField.defaultProps = {
  id: undefined,
  name: undefined,
  label: undefined,
  title: undefined,
  placeholder: undefined,
  format: dateFormat,
  value: null,
  required: false,
  touched: undefined,
  error: false,
  errors: [],
}

export default DateTimeField
