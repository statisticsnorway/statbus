import React from 'react'
import { func, shape, string, number, oneOfType } from 'prop-types'
import { Form } from 'semantic-ui-react'
import DatePicker from 'react-datepicker'

import { getDate, formatDate, dateFormat, toUtc } from 'helpers/dateHelper'

const SearchForm = ({ searchQuery, localize, onChange, onSubmit }) => {
  const handleChange = (_, { name, value }) => {
    onChange(name, value)
  }

  const handleDatePickerChange = name => (value) => {
    onChange(name, value === null ? searchQuery[name] : toUtc(value))
  }

  return (
    <Form onSubmit={onSubmit}>
      <Form.Group widths="equal">
        <div className="field datepicker">
          <label htmlFor="dateFrom">{localize('DateFrom')}</label>
          <DatePicker
            selected={getDate(searchQuery.dateFrom)}
            onChange={handleDatePickerChange('dateFrom')}
            dateFormat={dateFormat}
            className="ui input"
            type="number"
            name="dateFrom"
            value={searchQuery.dateFrom || formatDate(getDate())}
            id="dateFrom"
          />
        </div>
        <div className="field datepicker">
          <label htmlFor="dateTo">{localize('DateTo')}</label>
          <DatePicker
            selected={getDate(searchQuery.dateTo)}
            onChange={handleDatePickerChange('dateTo')}
            dateFormat={dateFormat}
            className="ui input"
            type="number"
            name="dateTo"
            value={searchQuery.dateTo || formatDate(getDate())}
            id="dateTo"
          />
        </div>
      </Form.Group>
      <Form.Button
        icon="search"
        content={localize('Search')}
        type="submit"
        floated="right"
        primary
      />
    </Form>
  )
}

SearchForm.propTypes = {
  searchQuery: shape({
    dateFrom: string,
    dateTo: string,
  }),
  onChange: func.isRequired,
  onSubmit: func.isRequired,
  localize: func.isRequired,
}

SearchForm.defaultProps = {
  searchQuery: {
    dateFrom: formatDate(getDate()),
    dateTo: formatDate(getDate()),
  },
}

export default SearchForm
