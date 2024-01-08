import React from 'react'
import PropTypes from 'prop-types'
import { Table } from 'semantic-ui-react'

import TableItem from './Item.jsx'

const headerKeys = ['Id', 'Type', 'Year', 'Employees', 'Turnover']

const Page = ({ details, localize }) => (
  <div>
    <h2>Activities uploaded</h2>
    <Table selectable size="small" className="wrap-content">
      <Table.Header>
        <Table.Row>
          {headerKeys.map(key => <Table.HeaderCell key={key} content={localize(key)} />)}
          <Table.HeaderCell />
        </Table.Row>
      </Table.Header>
      <Table.Body>
        {details.activities.map(item => (
          <TableItem key={item.id} data={item} localize={localize} />
        ))}
      </Table.Body>
    </Table>
  </div>
)
const { arrayOf, func, shape } = PropTypes

Page.propTypes = {
  localize: func.isRequired,
  details: arrayOf(shape({})).isRequired,
}

export default Page
