import React from 'react'
import DatePicker from 'react-datepicker'

import { wrapper } from 'helpers/locale'
import { getDate, toUtc } from 'helpers/dateHelper'
import styles from './styles.pcss'

const DateField = ({ name, value, onChange, labelKey, localize }) => {
  const handleChange = (date) => {
    onChange(null, { name, value: toUtc(date) })
  }

  return (
    <div className={`field ${styles.datepicker}`}>
      <label>{localize(labelKey)}</label>
      <DatePicker
        name={name}
        className="ui input"
        onChange={handleChange}
        selected={getDate(value)}
      />
    </div>
  )
}

const { func, string } = React.PropTypes
DateField.propTypes = {
  onChange: func.isRequired,
  localize: func.isRequired,
  name: string.isRequired,
  value: string.isRequired,
  labelKey: string.isRequired,
}

export default wrapper(DateField)
