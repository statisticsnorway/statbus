import React from 'react'
import { func, shape, string, number, oneOfType } from 'prop-types'
import { Form } from 'semantic-ui-react'
import DatePicker from 'react-datepicker'

import { dataSourceQueueStatuses } from 'helpers/enums'
import { getDate, formatDate, dateFormat, toUtc } from 'helpers/dateHelper'

const types = [['any', 'AnyType'], ...dataSourceQueueStatuses]

const SearchForm = ({ searchQuery, localize, onChange, onSubmit }) => {
  const statusOptions = types.map(kv => ({ value: kv[0], text: localize(kv[1]) }))
  const status = statusOptions[Number(searchQuery.status) || 0].value

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
        <Form.Select
          name="status"
          value={status}
          onChange={handleChange}
          options={statusOptions}
          label={localize('Status')}
          size="large"
          search
        />
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
    status: oneOfType([number, string]),
  }),
  onChange: func.isRequired,
  onSubmit: func.isRequired,
  localize: func.isRequired,
}

SearchForm.defaultProps = {
  searchQuery: {
    dateFrom: formatDate(getDate()),
    dateTo: formatDate(getDate()),
    status: 0,
  },
}

export default SearchForm
