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
    }
  }

  onChangeWrapper = (ambiguousValue) => {
    const { name, onChange } = this.props
    const nextValue = this.ensure(ambiguousValue)
    this.setState({ isDateValid: true })
    onChange({ target: { name, value: nextValue } }, { ...this.props, value: nextValue })
  }

  onChangeRawWrapper = (event) => {
    const { name, onChange } = this.props
    const isEmpty = event.target.value === ''
    const parsed = dateFns.parse(event.target.value)
    const isDateValid = (!!parsed && parsed.isValid() && dateFns.isDateInThePast(parsed)) || isEmpty
    this.setState({ isDateValid })
    const nextValue = this.ensure(parsed)
    onChange(
      { target: { name, value: isDateValid ? nextValue : null } },
      { ...this.props, value: isDateValid ? nextValue : null },
    )
  }

  format = x => dateFns.formatDate(x, this.props.dateFormat)

  ensure = x => R.cond([[hasValue, R.pipe(this.format, dateFns.toUtc)], [R.T, R.identity]])(x)

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
      ...restProps
    } = this.props
    const hasErrors = touched !== false && hasValue(errorKeys)

    const label = labelKey !== undefined ? localize(labelKey) : undefined
    const title = titleKey ? localize(titleKey) : label
    const id =
      ambiguousId != null ? ambiguousId : ambiguousName != null ? ambiguousName : 'DateTimeField'

    const inputProps = {
      ...restProps,
      id,
      name: ambiguousName,
      title,
      required,
      as: DatePicker,
      selected: dateFns.getDateOrNull(value),
      error: error || hasErrors,
      placeholder: placeholderKey ? localize(placeholderKey) : label,
      className: 'ui input',
      onChange: this.onChangeWrapper,
      onChangeRaw: this.onChangeRawWrapper,
      maxDate: dateFns.now(),
    }
    return (
      <div
        className={`field datepicker${required ? ' required' : ''}${
          hasErrors || !this.state.isDateValid ? ' error' : ''
        }`}
      >
        {label !== undefined && <label htmlFor={id}>{label}</label>}
        <Form.Input {...inputProps} />
        {hasErrors && <Message title={label} list={errorKeys.map(localize)} compact error />}
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
