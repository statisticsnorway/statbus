import React from 'react'
import { Link } from 'react-router'

import queryObjToString from 'helpers/queryHelper'
import styles from './styles'

const Pagination = ({ currentPage, totalPages, queryObj, pathname }) => {
  const hrefs = [...Array(totalPages).keys()]
  .filter(x => x < 5 || x > totalPages - 5 || Math.abs(x - currentPage) < 5)
  .map(x => x != currentPage ?
    <Link key={x} to={`${pathname}?${queryObjToString({ ...queryObj, page: x })}`}>{x + 1}</Link>
    :
    <a key={x}>{x + 1}</a>)
  return (
    <div className={styles.root}>
      {hrefs}
    </div>
  )
}

const { number, string } = React.PropTypes

Pagination.propTypes = {
  currentPage: number,
  totalPages: number,
  pathname: string,
}

export default Pagination
