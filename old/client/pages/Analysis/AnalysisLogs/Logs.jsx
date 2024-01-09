import React from 'react'
import { func, bool, number, arrayOf, shape } from 'prop-types'
import { Segment, Table } from 'semantic-ui-react'

import Paginate from '/components/Paginate'
import Item from './Item.jsx'

const headerKeys = ['UnitName', 'UnitType', 'ProcessedAt', 'ResolvedAt', 'SummaryMessages']

const Logs = ({ items, localize, totalCount, fetching }) => (
  <div>
    <br />
    <h2>{localize('ViewAnalysisQueueLogs')}</h2>
    <Segment loading={fetching}>
      <Paginate totalCount={Number(totalCount)}>
        <Table selectable size="small" className="wrap-content">
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
              <Item key={item.id} data={item} localize={localize} />
            ))}
          </Table.Body>
        </Table>
      </Paginate>
    </Segment>
  </div>
)

Logs.propTypes = {
  localize: func.isRequired,
  totalCount: number.isRequired,
  items: arrayOf(shape).isRequired,
  fetching: bool.isRequired,
}

export default Logs
