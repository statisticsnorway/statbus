import React from 'react'

import { bool, arrayOf, func, string } from 'prop-types'
import DatePicker from 'react-datepicker'
import { Form, Message } from 'semantic-ui-react'
import R from 'ramda'

import * as dateFns from 'helpers/dateHelper'
import { hasValue } from 'helpers/validation'

class DateTimeField extends React.Component {
  constructor(props) {
    super(props)
    this.state = {
      isDateValid: true,
      errorMessages: [],
    }
  }

  onChangeWrapper = (ambiguousValue) => {
    const { name, onChange } = this.props
    const nextValue = dateFns.toUtc(ambiguousValue)
    this.setState({ isDateValid: true, errorMessages: [] })
    onChange({ target: { name, value: nextValue } }, { ...this.props, value: nextValue })
  }

  onChangeRawWrapper = (event) => {
    const { name, onChange } = this.props
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
    this.setState({ isDateValid, errorMessages })
    const nextValue = isEmpty ? '' : isDateValid ? this.ensure(parsed) : ''
    onChange({ target: { name, value: nextValue } }, { ...this.props, value: nextValue })
  }

  format = x => dateFns.formatDate(x, this.props.dateFormat)

  ensure = x =>
    R.cond([
      [
        hasValue,
        R.pipe(
          this.format,
          dateFns.toUtc,
        ),
      ],
      [R.T, R.identity],
    ])(x)

  render() {
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
      disabled,
      readOnly,
      ...restProps
    } = this.props
    const hasErrors = touched !== false && hasValue(errorKeys)

    const label = labelKey !== undefined ? localize(labelKey) : undefined
    const title = titleKey ? localize(titleKey) : label
    const id =
      ambiguousId != null ? ambiguousId : ambiguousName != null ? ambiguousName : 'DateTimeField'
    const filteredErrorMessages = errorKeys.filter(erKey => this.state.errorMessages.filter(stateKey => stateKey === erKey).length !== 1)
    filteredErrorMessages.forEach(el => this.state.errorMessages.push(el))

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
      onChange: this.onChangeWrapper,
      onChangeRaw: this.onChangeRawWrapper,
      maxDate: dateFns.now(),
      autoComplete: 'off',
    }

    return (
      <div
        className={`field datepicker${required ? ' required' : ''}
          ${hasErrors || !this.state.isDateValid ? ' error' : ''}
          ${disabled ? 'disabled' : ''}
        `}
      >
        {label !== undefined && <label htmlFor={id}>{label}</label>}
        DATETIME PICKER
        <Form.Input {...inputProps} />
        {(hasErrors || !this.state.isDateValid) && (
          <Message title={label} list={this.state.errorMessages.map(localize)} compact error />
        )}
      </div>
    )
  }
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
  value: undefined,
  required: false,
  touched: undefined,
  error: false,
  errors: [],
  popuplocalizedKey: undefined,
  disabled: false,
  readOnly: false,
}

export default DateTimeField
