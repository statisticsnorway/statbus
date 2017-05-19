import React from 'react'
import { Button, Form } from 'semantic-ui-react'

import dataSourceQueueStatuses from 'helpers/dataSourceQueueStatuses'
import DateField from 'components/StatUnitForm/fields/DateField'
import { wrapper } from 'helpers/locale'
import { getDate, formatDate } from 'helpers/dateHelper'
import styles from './styles'

const { func, shape, string, number, oneOfType } = React.PropTypes
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
          <DateField
            key="dateFromKey"
            name="dateFrom"
            value={searchQuery.dateFrom || formatDate(getDate())}
            onChange={this.handleChange}
            labelKey="DateFrom"
          />
          <DateField
            key="dateToKey"
            name="dateTo"
            value={searchQuery.dateTo || formatDate(getDate())}
            onChange={this.handleChange}
            labelKey="DateTo"
          />
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
