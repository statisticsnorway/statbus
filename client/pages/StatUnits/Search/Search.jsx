import React from 'react'
import { Link, browserHistory } from 'react-router'
import { Button } from 'semantic-ui-react'

import { systemFunction as sF } from 'helpers/checkPermissions'
import Pagination from 'components/Pagination'
import queryObjToString from 'helpers/queryHelper'
import { wrapper } from 'helpers/locale'
import SearchForm from './SearchForm'
import StatUnitList from './StatUnitList'
import styles from './styles'

class Search extends React.Component {

  componentWillReceiveProps(nextProps) {
    const { query: newQuery } = nextProps
    const { fetchStatUnits, query } = this.props
    if (JSON.stringify(query) !== JSON.stringify(newQuery)) {
      fetchStatUnits(newQuery)
    }
  }

  fetchStatUnit = (query) => {
    browserHistory.push(`statunits?${queryObjToString({ ...query, page: 0 })}`)
  }

  render() {
    const {
      statUnits, fetchStatUnits, deleteStatUnit, totalCount,
      totalPages, query, pathname, queryObj, localize
    } = this.props
    return (
      <div>
        <h2>{localize('StatUnitSearch')}</h2>
        {sF('StatUnitCreate')
          && <Button
            as={Link} to="/statunits/create"
            content={localize('CreateStatUnit')}
            icon="add square"
            size="medium"
            color="green"
          />}
        <SearchForm search={this.fetchStatUnit} query={query} />
        <div className={styles['list-root']}>
          {sF('StatUnitCreate')
            && <Link to="/statunits/create">{localize('Create')}</Link>}
          <StatUnitList {...{ statUnits, deleteStatUnit }} />
          <Pagination {...{ currentPage: query.page, totalPages, queryObj, pathname }} />
          <span>{localize('Total')}: {totalCount}</span>
          <span>{localize('TotalPages')}: {totalPages}</span>
        </div>
      </div>
    )
  }
}

Search.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(Search)
