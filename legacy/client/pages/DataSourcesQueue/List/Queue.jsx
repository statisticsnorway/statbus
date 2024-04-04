import React, { useState } from 'react'
import PropTypes from 'prop-types'
import { Segment, Table, Confirm } from 'semantic-ui-react'

import {
  getDate,
  getDateSubtractMonth,
  formatDateTimeEndOfDay,
  formatDateTimeStartOfDay,
} from '/helpers/dateHelper'
import Paginate from '/components/Paginate'
import Item from './Item.jsx'
import SearchForm from './SearchForm.jsx'

const headerKeys = [
  'DataSourceName',
  'DataSourceTemplateName',
  'UploadDateTime',
  'UserName',
  'Status',
  'Note',
]

function Queue({
  query,
  result,
  localize,
  fetching,
  totalCount,
  formData,
  actions: { setQuery, updateQueueFilter, deleteDataSourceQueue },
}) {
  const [selectedQueue, setSelectedQueue] = useState(undefined)
  const [showConfirm, setShowConfirm] = useState(false)
  const [isLoading, setIsLoading] = useState(false)

  const handleChangeForm = (name, value) => {
    updateQueueFilter({ [name]: value })
  }

  const handleSubmitForm = (e) => {
    e.preventDefault()
    setQuery({ ...query, ...formData })
  }

  const handleDelete = (queue) => {
    setSelectedQueue(queue)
    setShowConfirm(true)
  }

  const handleCancel = () => {
    setSelectedQueue(undefined)
    setShowConfirm(false)
  }

  const handleConfirm = () => {
    setIsLoading(true)
    deleteDataSourceQueue(selectedQueue.id).then(() => setIsLoading(false))
    handleCancel()
  }

  function renderConfirm() {
    return (
      <Confirm
        open={showConfirm}
        header={`${localize('AreYouSure')}`}
        content={`${localize('RejectDataSourceMessage')} "${
          selectedQueue.dataSourceTemplateName
        }"?`}
        onConfirm={handleConfirm}
        onCancel={handleCancel}
        confirmButton={localize('Ok')}
        cancelButton={localize('ButtonCancel')}
      />
    )
  }

  return (
    <div>
      <h2>{localize('DataSourceQueues')}</h2>
      {showConfirm && renderConfirm()}
      <Segment loading={fetching}>
        <SearchForm
          searchQuery={formData}
          onChange={handleChangeForm}
          onSubmit={handleSubmitForm}
          localize={localize}
        />
        <br />
        <br />
        <br />
        <Paginate totalCount={Number(totalCount)}>
          <Table selectable size="small" className="wrap-content" fixed>
            <Table.Header>
              <Table.Row>
                {headerKeys.map(key => (
                  <Table.HeaderCell key={key} content={localize(key)} />
                ))}
                <Table.HeaderCell />
                <Table.HeaderCell />
              </Table.Row>
            </Table.Header>
            <Table.Body>
              {result.map(item => (
                <Item
                  key={item.id}
                  data={item}
                  localize={localize}
                  deleteQueue={handleDelete}
                  isLoading={isLoading}
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
  localize: PropTypes.func.isRequired,
  result: PropTypes.arrayOf(PropTypes.shape({})).isRequired,
  totalCount: PropTypes.number.isRequired,
  actions: PropTypes.shape({
    updateQueueFilter: PropTypes.func.isRequired,
    setQuery: PropTypes.func.isRequired,
  }).isRequired,
  fetching: PropTypes.bool.isRequired,
  formData: PropTypes.shape({}).isRequired,
  query: PropTypes.shape({
    status: PropTypes.string,
    dateTo: PropTypes.string,
    dateFrom: PropTypes.string,
  }),
}

Queue.defaultProps = {
  query: {
    status: 'any',
    dateTo: formatDateTimeEndOfDay(getDate()),
    dateFrom: formatDateTimeStartOfDay(getDateSubtractMonth()),
  },
}

export default Queue
