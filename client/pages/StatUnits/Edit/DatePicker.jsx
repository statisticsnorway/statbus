import React from 'react'
import moment from 'moment'
import DatePicker from 'react-datepicker'
import styles from './styles'

const DatePickerWrap = ({ label, value, handleDateEdit, ...rest }) => (
  <div className={`field ${styles.datePicker}`}>
    <label>{label}</label>
    <DatePicker {...{ ...rest, className: 'ui input', selected: moment(value), onChange: handleDateEdit }} />
  </div>
)


export default DatePickerWrap
