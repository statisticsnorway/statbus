import React from 'react'
import { connect } from 'react-redux'
import { Menu, Icon } from 'semantic-ui-react'
import R from 'ramda'

import { formatDateTime } from 'helpers/dateHelper'
import { getPagesRange } from '../Paginate/utils.js'
import './styles'

const { string, number, func, any } = React.PropTypes

export const griddleSemanticStyle = {
  classNames: {
    Table: 'ui small selectable line table sortable',
    NextButton: 'ui button',
    Pagination: 'ui',
    PreviousButton: 'ui button',
    NoResults: 'ui message',
    Cell: 'wrap-content',
  },
}

export const EnhanceWithRowData = connect((state, { griddleKey }) => ({
  rowData: state.get('data').find(r => r.get('griddleKey') === griddleKey).toJSON(),
}))

export const GriddleDateColumn = ({ value }) => <span>{value && formatDateTime(value)}</span>

GriddleDateColumn.propTypes = {
  value: string.isRequired,
}

export const GriddlePaginationMenu = ({ currentPage, maxPages, setPage, className, style }) => {
  const pages = getPagesRange(currentPage, maxPages)
  return (
    <Menu pagination fluid className={className} style={style}>
      {pages.map((value) => {
        const disabled = value === currentPage || !R.is(Number, value)
        return (
          <Menu.Item
            key={value}
            content={value}
            disabled={disabled}
            onClick={disabled ? undefined : () => setPage(value)}
          />
        )
      })}
    </Menu>
  )
}

GriddlePaginationMenu.propTypes = {
  currentPage: number.isRequired,
  maxPages: number.isRequired,
  setPage: func.isRequired,
  className: string,
  style: any,
}

GriddlePaginationMenu.defaultProps = {
  className: undefined,
  style: undefined,
}

export const GriddlePagination = ({ PageDropdown, className, style }) => (
  <div className={className} style={style}>
    <PageDropdown />
  </div>
)

GriddlePagination.propTypes = {
  PageDropdown: func.isRequired,
  className: string,
  style: any,
}

GriddlePagination.defaultProps = {
  className: undefined,
  style: undefined,
}

export const GriddleSortableColumn = ({ title, icon }) => {
  return (
    <span>
      {title}
      <span>{icon || <Icon name="sort" color="grey" />}</span>
    </span>
  )
}

GriddleSortableColumn.propTypes = {
  title: string,
  icon: string,
}

GriddleSortableColumn.defaultProps = {
  title: '',
  icon: null,
}
