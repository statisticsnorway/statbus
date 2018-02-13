import React from 'react'
import { func, shape, string, number, oneOfType } from 'prop-types'
import { Form } from 'semantic-ui-react'

import { DateTimeField } from 'components/fields'
import { dataSourceQueueStatuses } from 'helpers/enums'
import { getDate, formatDate } from 'helpers/dateHelper'

const types = [['any', 'AnyType'], ...dataSourceQueueStatuses]

const SearchForm = ({ searchQuery, localize, onChange, onSubmit }) => {
  const statusOptions = types.map(kv => ({ value: kv[0], text: localize(kv[1]) }))
  const status = statusOptions[Number(searchQuery.status) || 0].value

  const handleChange = (_, { name, value }) => {
    onChange(name, value)
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
