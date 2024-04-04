import React from 'react'
import { func, shape, string } from 'prop-types'
import { Form } from 'semantic-ui-react'

import { DateTimeField } from '/components/fields'
import { getDate, formatDate } from '/helpers/dateHelper'

const SearchForm = ({ searchQuery, localize, onChange, onSubmit }) => {
  const handleChange = (_, { name, value }) => {
    onChange(name, value === null ? searchQuery[name] : value)
  }
  return (
    <Form onSubmit={onSubmit}>
      <Form.Group widths="equal">
        <DateTimeField
          onChange={handleChange}
          name="dateFrom"
          value={searchQuery.dateFrom || formatDate(getDate())}
          label="DateFrom"
          localize={localize}
        />
        <DateTimeField
          onChange={handleChange}
          name="dateTo"
          value={searchQuery.dateTo || formatDate(getDate())}
          label="DateTo"
          localize={localize}
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
