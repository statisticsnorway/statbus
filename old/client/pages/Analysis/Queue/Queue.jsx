import React, { useState } from 'react'
import { func, bool, shape, number, string, arrayOf } from 'prop-types'
import { Segment, Table, Button, Confirm } from 'semantic-ui-react'
import { Link } from 'react-router'

import { getDate, formatDate } from '/helpers/dateHelper'
import Paginate from '/components/Paginate'
import Item from './Item.jsx'
import SearchForm from './SearchForm.jsx'

const headerKeys = [
  'UserStartPeriod',
  'UserEndPeriod',
  'ServerStartPeriod',
  'ServerEndPeriod',
  'User',
  'Comment',
]

const Queue = ({
  items,
  localize,
  totalCount,
  fetching,
  formData,
  query,
  actions: { updateQueueFilter, setQuery, deleteAnalyzeQueue },
}) => {
  const [selectedQueue, setSelectedQueue] = useState(undefined)
  const [showConfirm, setShowConfirm] = useState(false)
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
    deleteAnalyzeQueue(selectedQueue.id)
    handleCancel()
  }
  function renderConfirm() {
    return (
      <Confirm
        open={showConfirm}
        header={`${localize('AreYouSure')}`}
        content={`${localize('RejectAnalyzeSourceMessage')}`}
        onConfirm={handleConfirm}
        onCancel={handleCancel}
        confirmButton={localize('Ok')}
        cancelButton={localize('ButtonCancel')}
      />
    )
  }
  return (
    <div>
      <h2>{localize('AnalysisQueue')}</h2>
      {showConfirm && renderConfirm()}
      <Segment loading={fetching}>
        <div>
          <Button
            as={Link}
            to="/analysisqueue/create"
            content={localize('EnqueueNewItem')}
            icon="add square"
            size="medium"
            color="green"
          />
        </div>
        <br />
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
              </Table.Row>
            </Table.Header>
            <Table.Body>
              {items.map(item => (
                <Item key={item.id} data={item} localize={localize} deleteQueue={handleDelete} />
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
  totalCount: number.isRequired,
  actions: shape({
    updateQueueFilter: func.isRequired,
    setQuery: func.isRequired,
    deleteAnalyzeQueue: func.isRequired,
  }).isRequired,
  fetching: bool.isRequired,
  formData: shape({}).isRequired,
  query: shape({
    status: string,
    dateTo: string,
  }),
  items: arrayOf(shape({})).isRequired,
}

Queue.defaultProps = {
  query: {
    status: 'any',
    dateTo: formatDate(getDate()),
  },
}

export default Queue
