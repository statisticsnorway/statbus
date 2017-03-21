import React from 'react'
import { Menu } from 'semantic-ui-react'
import { Link } from 'react-router'
import R from 'ramda'

import { wrapper } from 'helpers/locale'
import styles from './styles'

const { node, number, func, oneOfType, shape, string } = React.PropTypes

class Paginate extends React.Component {

  static propTypes = {
    routing: shape({
      pathname: string,
      page: oneOfType([number, string]),
      pageSize: oneOfType([number, string]),
      queryString: string,
    }).isRequired,
    totalPages: oneOfType([number, string]),
    totalCount: oneOfType([number, string]),
    children: node.isRequired,
    localize: func.isRequired,
  }

  static defaultProps = {
    totalPages: 1,
    totalCount: 0,
  }

  renderPageSizeLink = (value) => {
    const { pathname, queryString, pageSize: ambiguousPageSize } = this.props.routing
    const pageSize = Number(ambiguousPageSize)

    const nextQueryString = queryString.includes(`pageSize=${pageSize}`)
      ? R.replace(`pageSize=${pageSize}`, `pageSize=${value}`, queryString)
      : queryString
        ? `${queryString}&pageSize=${value}`
        : `?pageSize=${value}`

    const isCurrent = value === pageSize
    const link = isCurrent
      ? <b>{value}</b>
      : <Link to={`${pathname}${nextQueryString}`}>{value}</Link>

    return (
      <Menu.Item
        key={value}
        content={value}
        disabled={isCurrent}
        as={() => link}
      />
    )
  }

  renderPageLink = (value) => {
    const { pathname, queryString, page: ambiguousPage } = this.props.routing
    const page = Number(ambiguousPage) || 1

    const nextQueryString = queryString.includes(`page=${page}`)
      ? R.replace(`page=${page}`, `page=${value}`, queryString)
      : queryString
        ? `${queryString}&page=${value}`
        : `?page=${value}`

    const isCurrent = value === page
    const link = isCurrent
      ? <b>{value}</b>
      : <Link to={`${pathname}${nextQueryString}`}>{value}</Link>

    return (
      <Menu.Item
        key={value}
        content={value}
        disabled={isCurrent}
        as={() => link}
      />
    )
  }

  render() {
    const { children, localize, totalCount, totalPages } = this.props

    const pageSizeLinks = [5, 10, 15, 25, 50]
      .map(this.renderPageSizeLink)

    const pageLinks = R.range(1, Number(totalPages) + 1)
      .map(this.renderPageLink)

    return (
      <div className={styles.root}>
        <Menu pagination className={styles.header}>
          <span className={styles.totalCount}>{localize('TotalCount')}: {Number(totalCount)}</span>
          <div className={styles.pageSizeLinks}>
            {localize('PageSize')}: {pageSizeLinks}
          </div>
        </Menu>
        {children}
        <Menu pagination className={styles.footer}>
          {localize('PageNum')}: {pageLinks}
        </Menu>
      </div>
    )
  }
}

export default wrapper(Paginate)
