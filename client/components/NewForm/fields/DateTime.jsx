import React from 'react'
import { bool, arrayOf, func, string } from 'prop-types'
import DatePicker from 'react-datepicker'
import { Message } from 'semantic-ui-react'

import Form from 'components/SchemaForm'
import { getDate, toUtc, dateFormat } from 'helpers/dateHelper'

const DateTime = ({
  name, value, onChange, labelKey, localize, required, errors,
}) => {
  const handleChange = (date) => {
    onChange({ name, value: date === null ? null : toUtc(date) })
  }
  const hasErrors = errors.length !== 0
  const label = localize(labelKey)
  return (
    <div className="field datepicker">
      <label htmlFor={name}>{label}</label>
      <Form.Text
        as={() => (
          <DatePicker
            selected={value === undefined || value === null
              ? null
              : getDate(value)}
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

DateTime.propTypes = {
  onChange: func.isRequired,
  localize: func.isRequired,
  name: string.isRequired,
  value: string.isRequired,
  labelKey: string.isRequired,
  required: bool,
  errors: arrayOf(string),
}

DateTime.defaultProps = {
  required: false,
  errors: [],
}

export default DateTime
