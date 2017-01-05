import React from 'react'
import { Link } from 'react-router'

import { systemFunction as sF } from 'helpers/checkPermissions'
import SearchForm from './SearchForm'
import StatUnitList from './StatUnitList'
import { wrapper } from 'helpers/locale'
import styles from './styles'

const Search = ({
  statUnits, fetchStatUnits, deleteStatUnit, totalCount, totalPages, localize,
}) => (
  <div>
    <SearchForm search={fetchStatUnits} />
    <div className={styles['list-root']}>
      {sF('StatUnitCreate') && <Link to="/statunits/create">{localize('Create')}</Link>}
      <div className={styles.laydown}>
        <StatUnitList {...{ statUnits, deleteStatUnit }} />
      </div>
    </div>
    <span>{localize('Total')}: {totalCount}</span>
    <br />
    <span>{localize('TotalPages')}: {totalPages}</span>
  </div>
)

Search.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(Search)
