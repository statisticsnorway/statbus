import React from 'react'
import { func, string } from 'prop-types'
import DatePicker from 'react-datepicker'

import { getDate, toUtc, dateFormat } from 'helpers/dateHelper'

const Calendar = ({ name, value, onChange, labelKey, localize }) => {
  const handleChange = (date) => {
    onChange(undefined, { name, value: date === null ? null : toUtc(date) })
  }
  const label = localize(labelKey)
  return (
    <div className="field datepicker">
      <label htmlFor={name}>{label}</label>
      <DatePicker
        selected={value === '' ? '' : getDate(value)}
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
