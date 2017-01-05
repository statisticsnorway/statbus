import React from 'react'
import { Table, Menu, Icon } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'

const TableFooter = ({ totalCount, totalPages, localize }) => (
  <Table.Footer>
    <Table.Row >
      <Table.HeaderCell colSpan="1">
        <span>{localize('TotalUsers')}: { totalCount }</span>
        <br />
        <span>{localize('TotalPages')}: {totalPages }</span>
      </Table.HeaderCell>
      <Table.HeaderCell colSpan="3">
        <Menu pagination>
          <Menu.Item as="a" icon>
            <Icon name="left chevron" />
          </Menu.Item>
          <Menu.Item as="a" content="1" />
          <Menu.Item as="a" icon>
            <Icon name="right chevron" />
          </Menu.Item>
        </Menu>
      </Table.HeaderCell>
    </Table.Row>
  </Table.Footer>
)

TableFooter.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(TableFooter)
