import React from 'react'
import { func, arrayOf, bool, shape, number, string } from 'prop-types'
import { Segment, Table } from 'semantic-ui-react'

import { getDate, formatDate } from 'helpers/dateHelper'
import Paginate from 'components/Paginate'
import styles from './styles.pcss'
import DataSourceQueueItem from './Item'
import SearchForm from './SearchForm'

const Queue = ({
  query, result, localize, fetching, totalCount, formData,
  actions: { setQuery, updateQueueFilter },
}) => {
  const handleChangeForm = (name, value) => {
    updateQueueFilter({ [name]: value })
  }

  const handleSubmitForm = (e) => {
    e.preventDefault()
    setQuery({ ...query, ...formData })
  }

  return (
    <div>
      <h2>{localize('DataSourceQueues')}</h2>
      <Segment loading={fetching}>
        <SearchForm
          searchQuery={formData}
          onChange={handleChangeForm}
          onSubmit={handleSubmitForm}
          localize={localize}
        />
        <br />
        <Paginate totalCount={Number(totalCount)}>
          <Table selectable size="small" className={styles.wrap}>
            <Table.Header>
              <Table.Row>
                <Table.HeaderCell>{localize('DataSourceName')}</Table.HeaderCell>
                <Table.HeaderCell>{localize('DataSourceTemplateName')}</Table.HeaderCell>
                <Table.HeaderCell>{localize('UploadDateTime')}</Table.HeaderCell>
                <Table.HeaderCell>{localize('UserName')}</Table.HeaderCell>
                <Table.HeaderCell>{localize('Status')}</Table.HeaderCell>
              </Table.Row>
            </Table.Header>
            <Table.Body>
              {result.map(item => (
                <DataSourceQueueItem
                  key={item.id}
                  data={item}
                  localize={localize}
                />
              ))}
            </Table.Body>
          </Table>
        </Paginate>
      </Segment>
    </div>
  )
}

Queue.propTypes = {
  localize: func.isRequired,
  result: arrayOf(shape({})).isRequired,
  totalCount: number.isRequired,
  actions: shape({
    updateQueueFilter: func.isRequired,
    setQuery: func.isRequired,
  }).isRequired,
  fetching: bool.isRequired,
  formData: shape({}).isRequired,
  query: shape({
    status: string,
    dateTo: string,
  }),
}

Queue.defaultProps = {
  query: {
    status: 'any',
    dateTo: formatDate(getDate()),
  },
}

export default Queue
