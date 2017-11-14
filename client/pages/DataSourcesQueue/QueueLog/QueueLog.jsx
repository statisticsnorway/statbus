import React from 'react'
import PropTypes from 'prop-types'
import { Segment, Table, Header } from 'semantic-ui-react'

import Paginate from 'components/Paginate'
import Item from './Item'

const headerKeys = ['Id', 'Name', 'Started', 'Ended', 'StatId', 'Status', 'Note']

const QueueLog = ({ result, totalCount, fetching, localize }) => (
  <Segment loading={fetching}>
    <Header as="h2" />
    <Paginate totalCount={Number(totalCount)}>
      <Table size="small" selectable>
        <Table.Header>
          <Table.Row>
            {headerKeys.map(key => <Table.HeaderCell key={key} content={localize(key)} />)}
            <Table.HeaderCell />
          </Table.Row>
        </Table.Header>
        <Table.Body>
          {result.map(item => <Item key={item.id} data={item} localize={localize} />)}
        </Table.Body>
      </Table>
    </Paginate>
  </Segment>
)

const { arrayOf, shape, bool, oneOfType, string, number, func } = PropTypes
QueueLog.propTypes = {
  result: arrayOf(shape({})).isRequired,
  fetching: bool.isRequired,
  totalCount: oneOfType([string, number]).isRequired,
  localize: func.isRequired,
}

export default QueueLog
