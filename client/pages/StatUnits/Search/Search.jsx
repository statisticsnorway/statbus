import React from 'react'
import { Link } from 'react-router'

import SearchForm from './SearchForm'
import StatUnitList from './StatUnitList'
import { systemFunction as sF } from '../../../helpers/checkPermissions'
import styles from './styles'

export default ({
  statUnits, fetchStatUnits, deleteStatUnit, totalCount, totalPages,
}) => (
  <div>
    <h2>Search statistical units</h2>
    <SearchForm search={fetchStatUnits} />
    <div className={styles['list-root']}>
      {sF('StatUnitCreate') && <Link to="/statunits/create">Create</Link>}
      <StatUnitList {...{ statUnits, deleteStatUnit }} />
      <span>total: {totalCount}</span>
      <span>pages: {totalPages}</span>
    </div>
  </div>
)
