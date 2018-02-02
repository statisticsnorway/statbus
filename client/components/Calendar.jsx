import React from 'react'
import { func, string } from 'prop-types'
import DatePicker from 'react-datepicker'

import { getDateOrNull, toUtc, dateFormat } from 'helpers/dateHelper'
import { hasValue } from 'helpers/validation'

const Calendar = ({ name, value, onChange, labelKey, localize }) => {
  const handleChange = (date) => {
    onChange(undefined, { name, value: hasValue(date) ? toUtc(date) : null })
  }
  const label = localize(labelKey)
  return (
    <div className="field datepicker">
      <label htmlFor={name}>{label}</label>
      <DatePicker
        selected={getDateOrNull(value)}
        name={name}
        value={value}
        onChange={handleChange}
        dateFormat={dateFormat}
        className="ui input"
      />
    </div>
  )
}

Calendar.propTypes = {
  onChange: func.isRequired,
  localize: func.isRequired,
  name: string.isRequired,
  value: string.isRequired,
  labelKey: string.isRequired,
}

export default Calendar
