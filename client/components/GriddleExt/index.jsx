import React from 'react'
import { connect } from 'react-redux'

import { formatDateTime } from 'helpers/dateHelper'
import './styles'

export const griddleSemanticStyle = {
  classNames: {
    Table: 'ui small selectable line table sortable',
    NextButton: 'ui button',
    Pagination: 'ui',
    PreviousButton: 'ui button',
    PageDropdown: 'ui dropdown',
    NoResults: 'ui message',
    Cell: 'wrap-content',
  },
}

export const EnhanceWithRowData = connect((state, { griddleKey }) => ({
  rowData: state.get('data').find(r => r.get('griddleKey') === griddleKey).toJSON(),
}))

export const GriddleDateColumn = ({ value }) => <span>{value && formatDateTime(value)}</span>

GriddleDateColumn.propTypes = {
  value: React.PropTypes.string.isRequired,
}
