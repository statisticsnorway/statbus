import React from 'react'
import { Link } from 'react-router'

import { systemFunction as sF } from 'helpers/checkPermissions'
import SearchForm from './SearchForm'
import StatUnitList from './StatUnitList'
import { wrapper } from 'helpers/locale'
import styles from './styles'
import Pagination from 'components/Pagination'


class Search extends React.Component {
  componentWillReceiveProps(nextProps) {
    const { query: newQuery } = nextProps
    const { fetchStatUnits, query } = this.props
    if (query.page !== newQuery.page) {
      fetchStatUnits(newQuery)
    }
  }

  render() {
    const { statUnits, fetchStatUnits, deleteStatUnit,
       totalCount, totalPages, query, pathname, queryObj, localize } = this.props
    const fetchStatUnitsWrap = x => fetchStatUnits({ ...x, page: 0 })
    return (
      <div>
        <h2>{localize('StatUnitSearch')}</h2>
        <SearchForm search={fetchStatUnitsWrap} query={query} />
        <div className={styles['list-root']}>
          {sF('StatUnitCreate') && <Link to="/statunits/create">{localize('Create')}</Link>}
          <StatUnitList {...{ statUnits, deleteStatUnit }} />
          <Pagination {...{ currentPage: query.page, totalPages, queryObj, pathname }} />
          <span>{localize('Total')}: {totalCount}</span>
          <span>{localize('TotalPages')}: {totalPages}</span>
        </div>
      </div>)
  }
}

Search.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(Search)

