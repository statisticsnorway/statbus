import React from 'react'
import { bool, arrayOf, func, string } from 'prop-types'
import DatePicker from 'react-datepicker'
import { Form, Message } from 'semantic-ui-react'
import R from 'ramda'

import * as dateFns from 'helpers/dateHelper'
import { hasValue, hasValueAndInThePast } from 'helpers/validation'

const DateTimeField = (rootProps) => {
  const {
    id: ambiguousId,
    name: ambiguousName,
    value,
    onChange,
    label: labelKey,
    title: titleKey,
    placeholder: placeholderKey,
    touched,
    error,
    required,
    errors: errorKeys,
    localize,
    popuplocalizedKey,
    ...restProps
  } = rootProps
  const hasErrors = touched !== false && hasValue(errorKeys)

  const label = labelKey !== undefined ? localize(labelKey) : undefined
  const title = titleKey ? localize(titleKey) : label
  const id =
    ambiguousId != null ? ambiguousId : ambiguousName != null ? ambiguousName : 'DateTimeField'
  const format = x => dateFns.formatDate(x, restProps.dateFormat)

  const ensure = R.cond([
    [hasValueAndInThePast, R.pipe(format, dateFns.toUtc)],
    [hasValue, () => R.pipe(format, dateFns.toUtc)(dateFns.now())],
    [R.T, R.identity],
  ])
  const inputProps = {
    ...restProps,
    id,
    name: ambiguousName,
    value: hasValue(value) ? format(value) : '',
    title,
    required,
    as: DatePicker,
    selected: dateFns.getDateOrNull(value),
    error: error || hasErrors,
    onChange: (ambiguousValue) => {
      const nextValue = ensure(ambiguousValue)
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
  dateFormat: string,
  required: bool,
  touched: bool,
  error: bool,
  errors: arrayOf(string),
  localize: func.isRequired,
  popuplocalizedKey: string,
}

DateTimeField.defaultProps = {
  id: undefined,
  name: undefined,
  label: undefined,
  title: undefined,
  placeholder: undefined,
  dateFormat: dateFns.dateFormat,
  value: null,
  required: false,
  touched: undefined,
  error: false,
  errors: [],
  popuplocalizedKey: undefined,
}

export default DateTimeField
