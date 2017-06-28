import React from 'react'
import { func, shape, string, number, oneOfType } from 'prop-types'
import { Button, Form } from 'semantic-ui-react'
import DatePicker from 'react-datepicker'

import dataSourceQueueStatuses from 'helpers/dataSourceQueueStatuses'
import { wrapper } from 'helpers/locale'
import { getDate, formatDate, dateFormat, toUtc } from 'helpers/dateHelper'
import styles from './styles.pcss'

class SearchForm extends React.Component {

  static propTypes = {
    searchQuery: shape({
      dateFrom: string,
      dateTo: string,
      status: oneOfType([number, string]),
    }).isRequired,
    onChange: func.isRequired,
    onSubmit: func.isRequired,
    localize: func.isRequired,
  }

  static defaultProps = {
    searchQuery: {
      dateFrom: formatDate(getDate()),
      dateTo: formatDate(getDate()),
      status: 0,
    },
  }

  handleChange = (_, { name, value }) => {
    this.props.onChange(name, value)
  }

  handleDatePickerChange = name => (value) => {
    this.props.onChange(
      name,
      value === null ? this.props.searchQuery[name] : toUtc(value),
    )
  }

  render() {
    const { searchQuery, localize, onSubmit } = this.props

    const defaultStatus = { value: 'any', text: localize('AnyType') }
    const statusOptions = [
      defaultStatus,
      ...[...dataSourceQueueStatuses].map(([key, value]) => ({
        value: key, text: localize(value),
      })),
    ]
    const status = statusOptions[Number(searchQuery.status) || 0].value
    return (
      <Form onSubmit={onSubmit} className={styles.form}>
        <Form.Group widths="equal">
          <div className={`field ${styles.datepicker}`}>
            <label htmlFor="dateFrom">{localize('DateFrom')}</label>
            <DatePicker
              selected={getDate(searchQuery.dateFrom)}
              onChange={this.handleDatePickerChange('dateFrom')}
              dateFormat={dateFormat}
              className="ui input"
              type="number"
              name="dateFrom"
              value={searchQuery.dateFrom || formatDate(getDate())}
              id="dateFrom"
            />
          </div>
          <div className={`field ${styles.datepicker}`}>
            <label htmlFor="dateTo">{localize('DateTo')}</label>
            <DatePicker
              selected={getDate(searchQuery.dateTo)}
              onChange={this.handleDatePickerChange('dateTo')}
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
            onChange={this.handleChange}
            options={statusOptions}
            label={localize('Status')}
            size="large"
            search
          />
        </Form.Group>
        <Form.Group inline>
          <Button
            className={styles.sybbtn}
            floated="right"
            icon="search"
            content={localize('Search')}
            type="submit"
            primary
          />
        </Form.Group>
      </Form>
    )
  }
}

export default wrapper(SearchForm)
