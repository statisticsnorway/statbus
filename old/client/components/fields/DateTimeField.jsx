import React, { useState } from 'react'
import { bool, arrayOf, func, string } from 'prop-types'
import DatePicker from 'react-datepicker'
import { Form, Message } from 'semantic-ui-react'
import * as R from 'ramda'
import * as dateFns from '/helpers/dateHelper'
import { hasValue } from '/helpers/validation'

export function DateTimeField({
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
  disabled,
  readOnly,
  ...restProps
}) {
  const [isDateValid, setIsDateValid] = useState(true)
  const [errorMessages, setErrorMessages] = useState([])

  const onChangeWrapper = (ambiguousValue) => {
    const { name } = restProps
    const nextValue = ensure(ambiguousValue)
    setIsDateValid(true)
    setErrorMessages([])
    onChange({ target: { name, value: nextValue } }, { ...restProps, value: nextValue })
  }

  const onChangeRawWrapper = (event) => {
    const { name } = restProps
    const isEmpty = event.target.value === ''
    const parsed = dateFns.parse(event.target.value && event.target.value.slice(0, 10))
    const isDateValid = (!!parsed && parsed.isValid() && dateFns.isDateInThePast(parsed)) || isEmpty
    const errorMessages =
      isDateValid && !!parsed
        ? []
        : !parsed.isValid()
          ? ['DateNotValid']
          : !dateFns.isDateInThePast(parsed)
            ? ['DateCantBeInFuture']
            : ['DateNotValid']
    setIsDateValid(isDateValid)
    setErrorMessages(errorMessages)
    const nextValue = isEmpty ? '' : isDateValid ? ensure(parsed) : ''
    onChange({ target: { name, value: nextValue } }, { ...restProps, value: nextValue })
  }

  const format = x => dateFns.formatDate(x, restProps.dateFormat)

  const ensure = x =>
    R.cond([
      [hasValue, R.pipe(format, dateFns.toUtc)],
      [R.T, R.identity],
    ])(x)

  const label = labelKey !== undefined ? localize(labelKey) : undefined
  const title = titleKey ? localize(titleKey) : label
  const id =
    ambiguousId != null ? ambiguousId : ambiguousName != null ? ambiguousName : 'DateTimeField'

  const hasErrors = touched !== false && hasValue(errorKeys)

  const inputProps = {
    ...restProps,
    id,
    name: ambiguousName,
    title,
    required,
    as: DatePicker,
    disabled: disabled || readOnly,
    selected: dateFns.getDateOrNull(value),
    error: error || hasErrors,
    placeholder: placeholderKey ? localize(placeholderKey) : label,
    className: 'ui input',
    onChange: onChangeWrapper,
    onChangeRaw: onChangeRawWrapper,
    maxDate: dateFns.now(),
    autoComplete: 'off',
  }

  return (
    <div
      className={`field datepicker${required ? ' required' : ''}
          ${hasErrors || !isDateValid ? ' error' : ''}
          ${disabled ? 'disabled' : ''}
        `}
      data-tooltip={popuplocalizedKey ? localize(popuplocalizedKey) : null}
      data-position="top left"
    >
      {label !== undefined && <label htmlFor={id}>{label}</label>}
      <Form.Input {...inputProps} />
      {(hasErrors || !isDateValid) && (
        <Message title={label} list={errorMessages.map(localize)} compact error />
      )}
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
  disabled: bool,
  readOnly: bool,
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
  disabled: false,
  readOnly: false,
}
