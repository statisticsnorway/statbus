import React from 'react'
import DatePicker from 'react-datepicker'
import { Message } from 'semantic-ui-react'

import Form from 'components/Form'
import { getDate, toUtc, dateFormat } from 'helpers/dateHelper'
import styles from './styles.pcss'

const DateField = ({
  name, value, onChange, labelKey, localize, required, errors,
}) => {
  const handleChange = (date) => {
    onChange({ name, value: date === null ? value : toUtc(date) })
  }
  const hasErrors = errors.length !== 0
  const label = localize(labelKey)
  return (
    <div className={`field ${styles.datepicker}`}>
      <label htmlFor={name}>{label}</label>
      <Form.Text
        as={() => (
          <DatePicker
            selected={getDate(value)}
            value={value}
            onChange={handleChange}
            dateFormat={dateFormat}
            className="ui input"
          />
        )}
        id={name}
        name={name}
        required={required}
        error={hasErrors}
      />
      <Form.Error at={name} />
      {hasErrors && <Message error title={label} list={errors.map(localize)} />}
    </div>
  )
}

const { bool, arrayOf, func, string } = React.PropTypes
DateField.propTypes = {
  onChange: func.isRequired,
  localize: func.isRequired,
  name: string.isRequired,
  value: string.isRequired,
  labelKey: string.isRequired,
  required: bool,
  errors: arrayOf(string),
}

DateField.defaultProps = {
  required: false,
  errors: [],
}

export default DateField
